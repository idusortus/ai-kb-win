// Program.cs — complete implementation
using System.ClientModel;
using System.Text.Json;
using OpenAI;
using OpenAI.Chat;
using OpenAI.Embeddings;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddCors(o => o.AddDefaultPolicy(
    p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();
app.UseDefaultFiles();
app.UseStaticFiles();
app.UseCors();

var supabaseUrl = Environment.GetEnvironmentVariable("SUPABASE_URL")
    ?? throw new InvalidOperationException("SUPABASE_URL not set");
var supabaseKey = Environment.GetEnvironmentVariable("SUPABASE_SERVICE_KEY")
    ?? throw new InvalidOperationException("SUPABASE_SERVICE_KEY not set");

// --- Provider config (Ollama local by default, OpenAI if OPENAI_API_KEY is set) ---
OpenAIClient openai;
string embedModel;
string chatModel;

var openaiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY");
if (!string.IsNullOrEmpty(openaiKey))
{
    openai     = new OpenAIClient(openaiKey);
    embedModel = Environment.GetEnvironmentVariable("EMBED_MODEL") ?? "text-embedding-3-small";
    chatModel  = Environment.GetEnvironmentVariable("CHAT_MODEL")  ?? "gpt-4o-mini";
    Console.WriteLine("Using OpenAI cloud");
}
else
{
    var ollamaUrl = Environment.GetEnvironmentVariable("OLLAMA_BASE_URL")
                    ?? "http://localhost:11434/v1";
    openai     = new OpenAIClient(new ApiKeyCredential("ollama"),
                     new OpenAIClientOptions { Endpoint = new Uri(ollamaUrl) });
    embedModel = Environment.GetEnvironmentVariable("EMBED_MODEL") ?? "nomic-embed-text";
    chatModel  = Environment.GetEnvironmentVariable("CHAT_MODEL")  ?? "llama3.2:3b";
    Console.WriteLine($"Using Ollama local at {ollamaUrl}");
}

var supabase = new Supabase.Client(supabaseUrl, supabaseKey);
await supabase.InitializeAsync();

// POST /chat  — main query endpoint
app.MapPost("/chat", async (ChatRequest req, HttpResponse response) =>
{
    response.ContentType = "text/event-stream";
    response.Headers.Append("Cache-Control", "no-cache");
    response.Headers.Append("X-Accel-Buffering", "no");

    // 1. Embed the user query
    var embedClient = openai.GetEmbeddingClient(embedModel);
    var embedding   = await embedClient.GenerateEmbeddingAsync(req.Question);
    var vector      = embedding.Value.ToFloats().ToArray();

    // 2. Retrieve top-k chunks via Supabase RPC
    var result = await supabase.Rpc("match_chunks", new {
        query_embedding  = vector,
        match_count      = 5,
        filter_file_type = (string?)null   // null = search all formats
    });

    // 3. Build grounded context block
    //    Format: [filename (type)]  content
    var chunks = JsonSerializer.Deserialize<JsonElement[]>(result.Content ?? "[]")
                 ?? [];
    var context = string.Join("\n\n---\n\n",
        chunks.Select(c =>
            $"[{c.GetProperty("source").GetString()} ({c.GetProperty("file_type").GetString()})]" +
            $"\n{c.GetProperty("content").GetString()}"
        ));

    var systemPrompt = $"""
        You are a knowledgeable assistant with access to the company's documents.
        Answer the question using ONLY the context provided below.
        Always cite your source using the filename shown in brackets.
        If the context does not contain enough information to answer,
        say so clearly — do not guess or invent details.

        CONTEXT:
        {context}
        """;

    // 4. Stream response via SSE
    var chatClient = openai.GetChatClient(chatModel);
    var messages   = new List<ChatMessage> { new SystemChatMessage(systemPrompt) };

    // Append conversation history for multi-turn context
    if (req.History is { Length: > 0 })
    {
        foreach (var turn in req.History)
        {
            if (turn.Role == "user")
                messages.Add(new UserChatMessage(turn.Content));
            else if (turn.Role == "assistant")
                messages.Add(new AssistantChatMessage(turn.Content));
        }
    }
    messages.Add(new UserChatMessage(req.Question));

    await foreach (var chunk in chatClient.CompleteChatStreamingAsync(messages))
    {
        foreach (var part in chunk.ContentUpdate)
            await response.WriteAsync($"data: {part.Text}\n\n");
    }

    // Emit source metadata so the UI can render citations
    var sourcesList = chunks.Select(c => new {
        source    = c.GetProperty("source").GetString(),
        file_type = c.GetProperty("file_type").GetString(),
        similarity = c.GetProperty("similarity").GetDouble()
    });
    await response.WriteAsync(
        $"data: [SOURCES]{JsonSerializer.Serialize(sourcesList)}\n\n");
    await response.WriteAsync("data: [DONE]\n\n");
});

// GET /health — quick smoke test
app.MapGet("/health", () => Results.Ok(new { status = "ok", ts = DateTime.UtcNow }));

app.Run();

record ChatRequest(string Question, ChatTurn[]? History = null);
record ChatTurn(string Role, string Content);
