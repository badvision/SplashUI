// S2b fixture, its own file for byte fidelity: the REAL 1.7.3 keg's
// server/serve_options.py SERVE_OPTIONS table (the Homebrew bottle's,
// extracted to /tmp without touching the installed keg) — the same 37 flags
// in the same order as 1.7.2's: the real 1.7.3 file diffs from 1.7.2's by the
// --max-image-pixels help string only (a mention of the Inkling-2-Mini patch),
// which the s2b parser does not read (flags, groups, env, secret, action,
// choices, defaults). The body below is a verbatim copy of the file's table;
// the suite's byte-check re-derives it from this literal.
let fixtureServeOptions173 = #"""

SERVE_OPTIONS = (
    ServeOption(
        "--host",
        "network",
        dict(
            type=parse_host,
            default="127.0.0.1",
            metavar="ADDRESS",
            help="HTTP bind address (default: 127.0.0.1; 0.0.0.0 for all IPv4 "
            "interfaces; unix:PATH for a UNIX socket); clients use an IP "
            "address, localhost or a name given with --allowed-host",
        ),
    ),
    ServeOption(
        "--allowed-host",
        "network",
        dict(
            action="append",
            default=[],
            metavar="HOST",
            help="additional HTTP Host name to accept, e.g. mymac.local; does not "
            "change the bind address (repeatable)",
        ),
    ),
    ServeOption(
        "--allowed-origin",
        "network",
        dict(
            action="append",
            default=[],
            type=parse_allowed_origin,
            metavar="ORIGIN",
            help="origin whose pages may call the API from a browser or webview, "
            "e.g. tauri://localhost; '*' for any (repeatable)",
        ),
        text=_origin_text,
    ),
    ServeOption(
        "--api-key",
        "network",
        dict(
            type=parse_api_key,
            metavar="KEY",
            help="require this key as a bearer token or x-api-key on every route "
            "but the chat page, /health and /ready (default: SPLASH_API_KEY)",
        ),
        environment="SPLASH_API_KEY",
        secret=True,
    ),
    ServeOption(
        "--no-webui",
        "network",
        dict(action="store_true", default=False, help="disable the chat page"),
    ),
    ServeOption(
        "--max-memory",
        "memory",
        dict(
            type=parse_max_memory,
            default=None,
            metavar="SIZE",
            help="Metal memory budget in place of the automatic one, e.g. 28G, up "
            "to the GPU's recommended working set less a margin (default: auto, "
            "which also leaves a tenth of the Mac's memory unwired)",
        ),
        engine=EngineArgument(1, text=_auto_text, required=True),
    ),
    ServeOption(
        "--max-context",
        "memory",
        dict(
            type=parse_max_context,
            default=None,
            metavar="TOKENS",
            help="context token limit, e.g. 100K or 1M (K = 1024 tokens, M = "
            "1000000 tokens), up to the model's limit, at most 1010000; past its "
            "native window a model with YaRN turns it on, which is static and "
            "changes answers at every length, so pass more than the native "
            "window only when a request needs it (default: auto, the native "
            "window when memory holds it)",
        ),
        engine=EngineArgument(0, text=_auto_text, required=True),
    ),
    ServeOption(
        "--ple-memory",
        "memory",
        dict(
            type=parse_ple_memory,
            default=None,
            metavar="SIZE",
            help="RAM row cache of the PLE n-gram table of a Qwen3.8-Flash-Next "
            "GGUF, e.g. 2G, which streams the rest from the SSD; off loads the "
            "whole table, tens of GB (default: auto, a cache of at most the "
            "rows of a 128K-token prompt, less where memory is short)",
        ),
        engine=EngineArgument("--ple-memory"),
        needs="ple_table",
    ),
    ServeOption(
        "--expert-memory",
        "memory",
        dict(
            type=parse_expert_memory,
            default=None,
            metavar="SIZE",
            help="RAM for the routed experts of a MoE model, e.g. 16G: they "
            "stream through a store of exactly this size, which neither grows "
            "nor gives memory back, and read the other experts from the SSD "
            "when a token routes them; a size that holds every expert, or "
            "off, loads them all (default: auto, which loads them all where "
            "memory holds them, and otherwise gives them what the context "
            "leaves, giving back down to their floor while requests need it; "
            "see streamed experts)",
        ),
        engine=EngineArgument("--expert-memory"),
        needs="experts",
    ),
    ServeOption(
        "--sparse-kv-memory",
        "memory",
        dict(
            type=parse_sparse_kv_memory,
            default=None,
            metavar="SIZE",
            help="RAM cache of the KV blocks a block-sparse model such as "
            "Qwen3.8-Flash-Next reads of requests whose KV is on the SSD, e.g. "
            "1200M; never below its floor (default: auto, its floor)",
        ),
        engine=EngineArgument("--sparse-kv-memory"),
        needs="sparse_kv",
    ),
    ServeOption(
        "--kv-format",
        "memory",
        dict(
            choices=("int8", "bf16"),
            default="int8",
            help="target KV cache storage (default: int8); bf16 uses more memory",
        ),
        engine=EngineArgument("--kv-format"),
    ),
    ServeOption(
        "--state-format",
        "memory",
        dict(
            choices=("fp32", "bf16"),
            default="fp32",
            help="recurrent state storage of running requests (default: fp32); "
            "bf16 halves each one's state, and cached states store int8 codes "
            "in either format unless --cached-states exact",
        ),
        engine=EngineArgument("--state-format"),
        needs="recurrent_state",
    ),
    ServeOption(
        "--cached-states",
        "memory",
        dict(
            choices=("int8", "exact"),
            default="int8",
            help="recurrent state storage of cached states (default: int8): int8 "
            "codes take about a quarter of an fp32 state, and a restored state "
            "can differ at near ties; exact keeps --state-format's, so a "
            "restore is exact",
        ),
        engine=EngineArgument("--cached-states"),
        needs="recurrent_state",
    ),
    ServeOption(
        "--idle-release",
        "memory",
        dict(
            type=parse_idle_release,
            default=None,
            metavar="DURATION",
            help="time without a request before the engine unwires its memory and "
            "frees the weights: seconds, or with an s, m or h suffix, e.g. 30m "
            "(default: 10m); off keeps both, though POST /v1/memory/release "
            "still frees the weights",
        ),
        text=idle_release_text,
        engine=EngineArgument("--idle-release", text=idle_release_text),
    ),
    ServeOption(
        "--max-cache-disk",
        "cache",
        dict(
            type=parse_max_cache_disk,
            default=None,
            metavar="SIZE",
            help="SSD quota for cached KV pages and states: auto follows the "
            "volume, a quarter of its free space beyond a floor of 10G (5%% of "
            "a volume under 200G), at most 32G; a size such as 16G is held as "
            "given while the volume keeps that floor; 0 disables (default: auto)",
        ),
        engine=EngineArgument(2),
    ),
    ServeOption(
        "--max-cache-disk-writes",
        "cache",
        dict(
            type=parse_max_cache_disk_writes,
            default=0,
            metavar="SIZE",
            help="the most the SSD cache writes a day, e.g. 200G; the state a "
            "conversation resumes from and KV pages pass it (default: 0, no "
            "limit)",
        ),
        engine=EngineArgument("--max-cache-disk-writes"),
    ),
    ServeOption(
        "--persistent-cache",
        "cache",
        dict(
            action="store_true",
            default=False,
            help="keep the SSD cache across restarts",
        ),
        engine=EngineArgument("--persistent-cache", text=_spelled("on")),
    ),
    ServeOption(
        "--cache-dir",
        "cache",
        dict(
            type=parse_cache_dir,
            default=None,
            metavar="DIRECTORY",
            help="where --persistent-cache keeps its files; needs "
            "--persistent-cache (default: ~/Library/Caches/Splash/prefix-cache)",
        ),
        engine=EngineArgument("--cache-dir"),
    ),
    ServeOption(
        "--served-model-name",
        "api",
        dict(
            action="append",
            default=[],
            type=parse_served_model_name,
            metavar="NAME",
            help="additional API model name (repeatable); responses report the "
            "loaded model ID unless --announce-served-name",
        ),
    ),
    ServeOption(
        "--announce-served-name",
        "api",
        dict(
            action="store_true",
            default=False,
            help="report the first --served-model-name in API responses and list "
            "it first in /v1/models; /status keeps the loaded model ID (needs "
            "--served-model-name)",
        ),
    ),
    ServeOption(
        "--sampling-default",
        "api",
        dict(
            action="append",
            default=[],
            type=parse_sampling_default,
            metavar="NAME=VALUE",
            help="the value of a sampling parameter for requests that set "
            "none (repeatable): "
            + ", ".join(SAMPLING_FIELDS)
            + " (default: the served family's published sampling for "
            "temperature, top_p and top_k, else the value that leaves the "
            "logits unchanged)",
        ),
        text=lambda item: f"{item[0]}={item[1]}",
    ),
    ServeOption(
        "--reasoning-effort",
        "api",
        dict(
            type=parse_reasoning_effort,
            metavar="EFFORT",
            help="effort of every Chat, Responses and Messages request, whatever "
            "the request asks: "
            + ", ".join(REASONING_EFFORTS[:-1])
            + f" or {REASONING_EFFORTS[-1]}; none turns thinking off (default: "
            "SPLASH_REASONING_EFFORT, else each request's own)",
        ),
        environment="SPLASH_REASONING_EFFORT",
        needs="reasoning_switch",
    ),
    ServeOption(
        "--default-reasoning-effort",
        "api",
        dict(
            type=parse_reasoning_effort,
            metavar="EFFORT",
            help="effort of Chat and Responses requests that set none: "
            + ", ".join(REASONING_EFFORTS[:-1])
            + f" or {REASONING_EFFORTS[-1]} (default: "
            "SPLASH_DEFAULT_REASONING_EFFORT, else the model template's)",
        ),
        environment="SPLASH_DEFAULT_REASONING_EFFORT",
        needs="reasoning_switch",
    ),
    ServeOption(
        "--thinking-token-budget",
        "api",
        dict(
            type=parse_thinking_token_budget,
            metavar="N",
            help="thinking tokens of a thinking request that sets no "
            "thinking_token_budget, after which its thinking closes (default: "
            "SPLASH_THINKING_TOKEN_BUDGET, else no cap)",
        ),
        environment="SPLASH_THINKING_TOKEN_BUDGET",
        needs="prompt_switches_reasoning",
    ),
    ServeOption(
        "--thinking-end-text",
        "api",
        dict(
            metavar="TEXT",
            help="text that ends thinking where a thinking budget runs out, such "
            "as a sentence that turns to the answer, then </think> as its last "
            f"token; at most {MAX_THINKING_END_TOKENS} tokens (default: "
            "SPLASH_THINKING_END_TEXT, else the close the chat template writes "
            "after a reasoning)",
        ),
        environment="SPLASH_THINKING_END_TEXT",
        needs="prompt_switches_reasoning",
    ),
    ServeOption(
        "--chat-template-file",
        "api",
        dict(
            type=parse_chat_template_file,
            default=None,
            metavar="FILE",
            help="a Jinja chat template to render every request with, in place "
            "of the model's own; read once at startup (default: the model's)",
        ),
    ),
    ServeOption(
        "--max-request-size",
        "requests",
        dict(
            type=parse_request_size,
            default=DEFAULT_MAX_REQUEST_BYTES,
            metavar="SIZE",
            help="maximum HTTP request body size, e.g. 128M (default: 128M); "
            "shared input budget is max(512M, twice this limit)",
        ),
    ),
    ServeOption(
        "--max-image-pixels",
        "requests",
        dict(
            type=parse_max_image_pixels,
            default=images.MAX_PIXELS,
            metavar="PIXELS",
            help=f"maximum resized pixels per image, {images.MIN_PIXELS}–"
            f"{images.MAX_PIXELS} (default: {images.MAX_PIXELS}); for "
            "Inkling-2-Mini, PIXELS / 256 is the most 20-pixel patches an "
            "image keeps its size within "
            f"({images.max_patches(images.MAX_PIXELS):,} at the default); "
            "bounds the vision scratch one image needs",
        ),
        engine=EngineArgument(
            "--max-image-patches", text=lambda pixels: str(images.max_patches(pixels))
        ),
        needs="vision",
    ),
    ServeOption(
        "--request-timeout",
        "requests",
        dict(
            type=parse_request_timeout,
            default=None,
            metavar="DURATION",
            help="time before a queued or in-flight request expires with 504: "
            "seconds, or with an s, m or h suffix, e.g. 30m (default: none)",
        ),
    ),
    ServeOption(
        "--queue-size",
        "requests",
        dict(
            type=parse_queue_size,
            default=DEFAULT_QUEUE_SIZE,
            metavar="REQUESTS",
            help="requests admitted at once, running or waiting; more get 503 "
            f"(default: {DEFAULT_QUEUE_SIZE})",
        ),
    ),
    ServeOption(
        "--max-concurrent-requests",
        "requests",
        dict(
            type=parse_concurrent_requests,
            default=DEFAULT_CONCURRENT_REQUESTS,
            metavar="REQUESTS",
            help="requests the engine runs at once, 1 to "
            f"{MAX_CONCURRENT_REQUESTS}; more let more clients be answered "
            "together, each a little slower, and take memory for their "
            "states and arenas: where that streams more of the weights or "
            "leaves less context than four would, the start logs both, and "
            "/status reports four's context (default: "
            f"{DEFAULT_CONCURRENT_REQUESTS})",
        ),
        engine=EngineArgument("--max-concurrent-requests"),
    ),
    ServeOption(
        "--decode-share",
        "requests",
        dict(
            type=parse_decode_share,
            default=None,
            metavar="SHARE",
            help="decode time owed per unit of prefill time while other requests "
            "decode (default: 0.5; 0 alternates one command each)",
        ),
        engine=EngineArgument("--decode-share"),
    ),
    ServeOption(
        "--disable-ane",
        "requests",
        dict(
            action="store_true",
            default=False,
            help="prefill on the GPU alone (default: a dense model's long "
            "prompts also use the Neural Engine when that is faster)",
        ),
        engine=EngineArgument("--ane", text=_spelled("off")),
        needs="dense_ffn",
    ),
    ServeOption(
        "--recalibrate-ane",
        "requests",
        dict(
            action="store_true",
            default=False,
            help="calibrate the Neural Engine's share of long prompts again at "
            "this start instead of taking the one this Mac kept",
        ),
        engine=EngineArgument("--ane-calibration", text=_spelled("again")),
        needs="dense_ffn",
    ),
    ServeOption(
        "--activations",
        "requests",
        dict(
            choices=("auto", "bf16"),
            default="auto",
            help="auto rounds activations to 8 bits where the GPU multiplies "
            "them twice as fast (M5 and later) and leaves the others bf16: "
            "long prompts through MLX 4- and 5-bit weights (about a quarter "
            "less time to the first token) and Q8_0 ones, rotated PQ2_0 decode "
            "and attention over the INT8 KV cache; bf16 keeps every activation "
            "bf16, for evaluations and bf16 parity (default: auto)",
        ),
        engine=EngineArgument("--activations"),
    ),
    ServeOption(
        "--verify-rows",
        "requests",
        dict(
            choices=("auto", "all"),
            default="auto",
            help="rows each decode cycle verifies: all verifies every row of "
            "a draft's block a lane, so greedy and seeded outputs repeat "
            "(default: auto, where each cycle takes the step of the most "
            "expected accepted tokens per cost, by the costs the Mac measured "
            "at a start and the cost of a long history and the acceptance "
            "learned from earlier cycles, or, on a model whose experts "
            "stream, the rows worth their time by its cycles' cost line, "
            "which is faster but lets those outputs differ from run to run)",
        ),
        engine=EngineArgument("--verify-rows"),
    ),
    ServeOption(
        "--allow-idle-sleep",
        "requests",
        dict(
            action="store_true",
            default=False,
            help="let the Mac sleep automatically while requests run (default: it "
            "stays awake until they finish; the display may still sleep)",
        ),
        engine=EngineArgument("--idle-sleep", text=_spelled("allow")),
    ),
)
"""#
