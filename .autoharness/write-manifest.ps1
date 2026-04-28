$ErrorActionPreference = 'Stop'
$WS = "c:\Users\hannov\OneDrive - Microsoft\Dev\AzureNamingTool"
Set-Location $WS

$list = Get-Content (Join-Path $WS '.autoharness/installed-artifacts.txt')
$artifacts = @()

foreach ($p in $list) {
    $full = Join-Path $WS $p
    if (-not (Test-Path $full)) { continue }
    $item = Get-Item $full
    if ($item.PSIsContainer) { continue }
    # Skip scaffolding markers (no template source)
    if ($p -like '*.gitkeep' -or $p -like '*installed-artifacts.txt') { continue }

    $sha = (Get-FileHash $full -Algorithm SHA256).Hash.ToLower()
    $type = 'instruction'
    $prim = 6
    # Compute template-relative path (under autoharness_home/templates/)
    $tmpl = $null
    if ($p -eq 'AGENTS.md') { $tmpl = 'foundation/AGENTS.md.tmpl' }
    elseif ($p -eq '.github/copilot-instructions.md') { $tmpl = 'foundation/copilot-instructions.md.tmpl' }
    elseif ($p -eq '.github/instructions/constitution.instructions.md') { $tmpl = 'foundation/constitution.instructions.md.tmpl' }
    elseif ($p -eq '.autoharness/config.yaml') { $tmpl = 'harness-config.yaml.tmpl' }
    elseif ($p -eq '.backlog/config.yml') { $tmpl = 'backlog/config.yml.tmpl' }
    elseif ($p -eq '.backlog/.stash.md') { $tmpl = 'backlog/stash.md.tmpl' }
    elseif ($p -like 'scripts/autoharness/*') {
        $name = Split-Path $p -Leaf
        $tmpl = "scripts/$name.tmpl"
        # file-lock and skill-search shell/ps1 scripts under skills are NOT .tmpl — handled below
    }
    elseif ($p -like '.github/instructions/*.instructions.md') {
        $name = Split-Path $p -Leaf
        $tmpl = "instructions/$name.tmpl"
    }
    elseif ($p -like '.github/agents/*') {
        $rel = $p.Substring('.github/agents/'.Length)
        $tmpl = "agents/$rel.tmpl"
    }
    elseif ($p -like '.github/skills/*') {
        $rel = $p.Substring('.github/skills/'.Length)
        # Scripts under skill 'scripts' subdir are raw (not .tmpl) — only SKILL.md is .tmpl
        if ($rel -like '*SKILL.md') {
            $tmpl = "skills/$rel.tmpl"
        } else {
            $tmpl = "skills/$rel"  # raw script
        }
    }
    elseif ($p -like '.github/policies/*') {
        $name = Split-Path $p -Leaf
        $tmpl = "policies/$name.tmpl"
    }
    elseif ($p -like '.github/prompts/*') {
        $name = Split-Path $p -Leaf
        $tmpl = "prompts/$name.tmpl"
    }
    else {
        $tmpl = $p  # fallback
    }

    if ($p -eq 'AGENTS.md' -or $p -like '*copilot-instructions.md' -or $p -like '*constitution.instructions.md') {
        $type = 'foundation'; $prim = 5
    }
    elseif ($p -like '.github/agents/*') { $type = 'agent'; $prim = 4 }
    elseif ($p -like '.github/skills/*SKILL.md') { $type = 'skill'; $prim = 4 }
    elseif ($p -like '.github/skills/*') { $type = 'script'; $prim = 4 }
    elseif ($p -like '.github/policies/*') { $type = 'policy'; $prim = 8 }
    elseif ($p -like '.github/prompts/*') { $type = 'prompt'; $prim = 6 }
    elseif ($p -like 'scripts/*') { $type = 'script'; $prim = 6 }
    elseif ($p -like '.backlog/*') { $type = 'config'; $prim = 8 }
    elseif ($p -like 'docs/*') { $type = 'config'; $prim = 9 }
    elseif ($p -like '.autoharness/*') { $type = 'config'; $prim = 8 }
    elseif ($p -like '.github/instructions/*') { $type = 'instruction'; $prim = 6 }

    $artifacts += [pscustomobject]@{
        path          = $p
        artifact_type = $type
        primitive     = $prim
        template      = $tmpl
        checksum      = $sha
    }
}

$profileHash = (Get-FileHash (Join-Path $WS '.autoharness/workspace-profile.yaml') -Algorithm SHA256).Hash.ToLower()
$configPath = Join-Path $WS '.autoharness/config.yaml'
$configHash = $null
if (Test-Path $configPath) {
    $configHash = (Get-FileHash $configPath -Algorithm SHA256).Hash.ToLower()
}

$installedAt = "2026-04-28T12:00:00Z"
$ahVersion = "0.0.0+local"
try {
    $v = (autoharness version 2>$null) -join ''
    if ($v) { $ahVersion = $v.Trim() }
} catch {}

# Build manifest as object
$manifest = [ordered]@{
    schema_version       = "1.0.0"
    installed_at         = $installedAt
    tuned_at             = $null
    autoharness_version  = $ahVersion
    autoharness_home     = "C:/Users/hannov/AppData/Roaming/uv/tools/autoharness/Lib/site-packages/autoharness/data"
    profile_hash         = $profileHash
    config_hash          = $configHash
    install_preset       = "standard"
    primary_stack_pack   = "web-app"
    stack_packs          = @("web-app", "api-service", "deployable-service")
    install_layers       = @("foundation", "instructions", "workflow", "review", "runtime", "backlog", "knowledge", "overlays")
    capability_packs     = @("continuous-learning", "strict-safety", "release-observability", "adversarial-review")
    capability_pack_overlays = @(
        [ordered]@{
            pack             = "continuous-learning"
            overlay_targets  = @("AGENTS.md", ".github/copilot-instructions.md", ".github/instructions/continuous-learning.instructions.md", ".github/skills/observe/SKILL.md", ".github/skills/learn/SKILL.md", ".github/skills/evolve/SKILL.md")
            verification_checks = @("instruction file present", "observe/learn/evolve skills present", "foundation references continuous-learning overlay")
        },
        [ordered]@{
            pack             = "strict-safety"
            overlay_targets  = @("AGENTS.md", ".github/copilot-instructions.md", ".github/instructions/strict-safety.instructions.md", ".github/skills/safety-modes/SKILL.md", ".github/skills/plan-harden/SKILL.md", ".github/skills/plan-review/SKILL.md")
            verification_checks = @("instruction file present", "safety-modes / plan-harden / plan-review skills present", "ProposedAction language threaded into foundation")
        },
        [ordered]@{
            pack             = "release-observability"
            overlay_targets  = @("AGENTS.md", ".github/copilot-instructions.md", ".github/instructions/release-observability.instructions.md", ".github/skills/operational-closure/SKILL.md", ".github/skills/runtime-verification/SKILL.md")
            verification_checks = @("instruction file present", "monitoring plan / observation window / rollback trigger language present in closure + runtime-verification")
        },
        [ordered]@{
            pack             = "adversarial-review"
            overlay_targets  = @("AGENTS.md", ".github/copilot-instructions.md", ".github/instructions/adversarial-review.instructions.md", ".github/agents/adversarial-review.agent.md")
            verification_checks = @("instruction file present", "adversarial-review agent installed", "consensus-weighted findings language threaded into review")
        }
    )
    primitives_installed = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    artifacts            = $artifacts
    variables_used       = [ordered]@{
        DATE = "2026-04-28"
        PROJECT_NAME = "AzureNamingTool"
        PRIMARY_LANGUAGE = "C#"
        PRIMARY_LANGUAGE_LOWER = "csharp"
        LANGUAGE_VERSION = ".NET 10.0"
        LANGUAGE_VERSION_DETAIL = "C# / .NET 10.0 (nullable enabled, implicit usings enabled)"
        LANGUAGE_NOTES = "(nullable reference types enabled; implicit usings enabled; suppresses CS8602/CS8600/CS1998)"
        LANGUAGE_FILE_GLOB = "**/*.cs,**/*.razor"
        DOC_COMMENT_STYLE = "/// <summary> XML doc comments"
        UNIMPLEMENTED_MARKER = 'throw new NotImplementedException("...");'
        ERROR_PATTERN = "throw typed exceptions; catch and translate at controller boundaries; v2 API returns ApiResponse<T>"
        UNSAFE_POLICY = 'No unsafe blocks; respect <Nullable>enable</Nullable>'
        BUILD_TOOL = "dotnet"
        BUILD_COMMAND = "dotnet build src/AzureNamingTool.csproj"
        BUILD_CHECK_COMMAND = "dotnet build src/AzureNamingTool.csproj --no-restore"
        TEST_RUNNER = "dotnet test (xunit)"
        TEST_COMMAND = "dotnet test tests/AzureNamingTool.UnitTests/AzureNamingTool.UnitTests.csproj"
        TEST_DIR = "tests/"
        SOURCE_DIR = "src/"
        LINTER = "roslyn analyzers (no external linter)"
        LINT_COMMAND = "dotnet build src/AzureNamingTool.csproj /warnaserror-:CS8602,CS8600,CS1998"
        FORMATTER = "dotnet format"
        FORMAT_COMMAND = "dotnet format src/AzureNamingTool.sln --verify-no-changes"
        FORMAT_CHECK_COMMAND = "dotnet format src/AzureNamingTool.sln --verify-no-changes"
        FORMAT_FIX_COMMAND = "dotnet format src/AzureNamingTool.sln"
        CI_PLATFORM = "GitHub Actions"
        CI_WORKFLOW_GLOB = "**/.github/workflows/*.yml"
        CI_NOTES = "GitHub Actions workflows under .github/workflows/. CI runs build + unit tests on push/PR."
        POLL_INTERVAL = "30"
        MAX_WAIT = "900"
        REPO_OWNER = "hannovdm"
        REPO_NAME = "AzureNamingTool"
        DEFAULT_BRANCH = "main"
        QUALITY_GATE_1_NAME = "build"
        QUALITY_GATE_1 = "dotnet build src/AzureNamingTool.csproj"
        QUALITY_GATE_2_NAME = "unit-test"
        QUALITY_GATE_2 = "dotnet test tests/AzureNamingTool.UnitTests/AzureNamingTool.UnitTests.csproj"
        QUALITY_GATE_3_NAME = "format-check"
        QUALITY_GATE_3 = "dotnet format src/AzureNamingTool.sln --verify-no-changes"
        QUALITY_GATE_4_NAME = "ui-test"
        QUALITY_GATE_4 = "dotnet test tests/AzureNamingTool.UiTests/AzureNamingTool.UiTests.csproj"
        REPOSITORY_OPERATING_MODEL = "Azure Naming Tool — ASP.NET Core Blazor Server (.NET 10.0). Layered architecture: Controllers (v1+v2) -> Services -> Repositories -> JSON or SQLite (EF Core, dual storage)."
        PROJECT_DESCRIPTION = "Azure Naming Tool — generate standardized Azure resource names via Blazor Server UI and v1+v2 REST APIs. Dual storage (FileSystem JSON / SQLite EF Core)."
        PROJECT_STRUCTURE = "src/ (Components, Controllers, Services, Repositories, Models, Helpers, Data, Middleware, Attributes, HealthChecks, repository, settings); tests/ (UnitTests, UiTests); docs/v5.0.0/adrs/; infra/."
        NAMING_CONVENTIONS = "PascalCase for types/members; camelCase for locals; interfaces prefixed I; async methods suffixed Async."
        NAMING_RULES = "PascalCase for types, methods, properties, public fields, namespaces. camelCase for locals, parameters, private fields. Interfaces prefixed with I. Async methods suffixed with Async."
        CODE_ORGANIZATION_RULES = "Layered architecture: Controllers -> Services -> Repositories -> Storage. Each service has IXxxService interface registered scoped in Program.cs. v2 controllers under Controllers/V2/ return ApiResponse<T>."
        ERROR_HANDLING_RULES = "Throw typed exceptions; never swallow. Translate at controller boundaries. v2 returns ApiResponse<T>; v1 returns ServiceResponse. Log via LogHelper."
        ERROR_HANDLING_CONVENTIONS = "Typed exceptions; controller-boundary translation; v2 returns ApiResponse<T>; v1 returns legacy ServiceResponse."
        ERROR_HANDLING_POLICY = "All exceptions MUST be typed, logged via LogHelper, and translated at controller boundaries. v2 endpoints return ApiResponse<T>."
        SAFETY_RULES = "<Nullable>enable</Nullable> on; respect annotations. No unsafe code. No reflection-based bypasses. File access resolves within workspace; reject path traversal. ApiKey validation runs before authorized actions."
        PERFORMANCE_RULES = "Prefer async/await; never .Result/.Wait(). Use IAsyncEnumerable<T> for streaming. Cache config via CacheHelper. Avoid materializing large LINQ-to-Entities lists."
        TESTING_RULES = "Tests in tests/AzureNamingTool.UnitTests/ (xunit + Moq + FluentAssertions). UI tests in tests/AzureNamingTool.UiTests/ (Playwright + LightBDD + NUnit, net8.0). AAA pattern. Class name mirrors SUT."
        DOCUMENTATION_RULES = "XML doc comments on public types and members. Inline <remarks> for non-obvious behavior. ADRs under docs/v5.0.0/adrs/."
        DOCUMENTATION_CONVENTIONS = "XML doc comments on public surfaces; ADRs in docs/v5.0.0/adrs/ for architecture-level decisions."
        DEPENDENCY_RULES = "Manage NuGet packages in src/AzureNamingTool.csproj. Pin to compatible major versions. New transitive deps require ADR justification."
        ANTI_PATTERNS = "Direct file/SQLite access from services; raw data from v2 controllers; hard-coded paths; missing [ApiKey] on new endpoints; catching Exception then re-throwing without context."
        LANGUAGE_SAFETY_CHECKS = "Nullability respected. No unsafe blocks. Endpoints carry [ApiKey]. Path-traversal protection. Secrets never logged."
        LANGUAGE_IDIOM_CHECKS = "Services follow IXxxService and registered scoped. Repositories used for storage access. v2 returns ApiResponse<T>. Async methods suffixed Async; no .Result/.Wait()."
        LANGUAGE_ERROR_HANDLING_CHECKS = "Typed exceptions; Exception not swallowed. Controller boundaries translate to HTTP + ApiResponse<T>/ServiceResponse. LogHelper used. Correlation ID propagated."
        LANGUAGE_PERFORMANCE_CHECKS = "No blocking calls in async paths. Cache reads via CacheHelper. EF Core queries shaped to needed fields. Large enumerations streamed."
        CONCURRENCY_PATTERNS = "async/await; IHttpContextAccessor (per-request); EF Core DbContext (scoped); ConcurrentDictionary in CacheHelper"
        LINT_POLICY = 'Build with no NEW analyzer warnings. Repo currently suppresses CS8602/CS8600/CS1998 -- do not widen suppression list without ADR.'
        TEST_STRUCTURE = "Unit tests in tests/AzureNamingTool.UnitTests/ (xunit); UI tests in tests/AzureNamingTool.UiTests/ (Playwright + LightBDD + NUnit, net8.0)."
        TEST_TIER_DESCRIPTION = "Unit (xunit + Moq + FluentAssertions) and UI (Playwright + LightBDD + NUnit, net8.0; requires running app)."
        COMMIT_SCOPES = "controllers, services, repositories, models, components, helpers, data, middleware, attributes, healthchecks, infra, docs, tests, ci"
        EXAMPLE_SCOPE = "controllers"
        MCP_SDK = "N/A (this workspace is not an MCP server)"
        MCP_TRANSPORT = "N/A"
        MCP_PROJECT_STRUCTURE = "N/A — Azure Naming Tool exposes REST APIs (v1 + v2), not an MCP server"
        ADDITIONAL_STACK_ROWS = "(see AGENTS.md technology table)"
        ADDITIONAL_COMMANDS = "(see AGENTS.md commands section)"
        BACKLOG_TOOL_NAME = "manual"
        BACKLOG_DIRECTORY = ".backlog"
        BACKLOG_TOOL_TYPE = "manual"
        BACKLOG_TOOLS = "none (manual file-based backlog)"
        STATUS_QUEUED = "queued"
        STATUS_ACTIVE = "active"
        STATUS_DONE = "done"
        STATUS_BLOCKED = "blocked"
        FIELD_TASK_ID = "id"
        FIELD_TITLE = "title"
        FIELD_STATUS = "status"
        FIELD_LABELS = "labels"
        FIELD_PARENT_ID = "parent_id"
        FIELD_TYPE = "type"
        FIELD_DESCRIPTION = "description"
        FEATURE_SHIPMENTS = "false"
        EXTENDED_OPERATIONS_TABLE = "_(no extended operations — manual file-based backlog)_"
        OP_CREATE_MCP = ""
        OP_LIST_MCP = ""
        OP_GET_MCP = ""
        OP_UPDATE_MCP = ""
        OP_MOVE_MCP = ""
        OP_SEARCH_MCP = ""
        OP_COMPLETE_MCP = ""
        OP_CREATE_CLI = ""
        OP_LIST_CLI = ""
        OP_GET_CLI = ""
        OP_UPDATE_CLI = ""
        OP_MOVE_CLI = ""
        OP_SEARCH_CLI = ""
        OP_COMPLETE_CLI = ""
        OP_CREATE_SHIPMENT_MCP = ""
        OP_GET_SHIPMENT_MCP = ""
        OP_LIST_SHIPMENTS_MCP = ""
        OP_CLAIM_SHIPMENT_MCP = ""
        OP_SHIP_SHIPMENT_MCP = ""
        OP_ADD_TO_SHIPMENT_MCP = ""
        OP_RETURN_BLOCKED_MCP = ""
        OP_CREATE_CHECKPOINT_MCP = ""
        OP_LIST_CHECKPOINTS_MCP = ""
        OP_GET_CHECKPOINT_MCP = ""
        OP_RESOLVE_CHECKPOINT_MCP = ""
        OP_POLL_HOOK_EVENTS_MCP = ""
        OP_ACK_HOOK_EVENTS_MCP = ""
        SUFFIX_FEATURE = "F"
        SUFFIX_CHORE = "C"
        SUFFIX_TASK = "T"
        SUFFIX_SPIKE = "SP"
        SUFFIX_DELIBERATION = "D"
        SUFFIX_BUG = "B"
        SUFFIX_EPIC = "E"
        SUFFIX_SUBTASK = "ST"
        SUFFIX_SHIPMENT = "S"
        DOCS_ROOT = "docs"
        DOCS_COMPOUND_DIR = "compound"
        DOCS_PLANS_DIR = "plans"
        DOCS_DECISIONS_DIR = "decisions"
        DOCS_MEMORY_DIR = "memory"
        DOCS_CLOSURE_DIR = "closure"
        DOCS_DESIGN_DOCS_DIR = "design-docs"
        DOCS_PRODUCT_SPECS_DIR = "product-specs"
        DOCS_COMPOUND = "docs/compound"
        DOCS_PLANS = "docs/plans"
        DOCS_DECISIONS = "docs/decisions"
        DOCS_MEMORY = "docs/memory"
        DOCS_CLOSURE = "docs/closure"
        DOCS_DESIGN_DOCS = "docs/design-docs"
        DOCS_PRODUCT_SPECS = "docs/product-specs"
        CONTINUOUS_LEARNING_DIR = ".autoharness/continuous-learning"
        CONTINUOUS_LEARNING_CAPTURE_HOOKS = "false"
        CONTINUOUS_LEARNING_ENVIRONMENT_ADAPTER = "none"
        CONTINUOUS_LEARNING_PROMOTION_THRESHOLD = "3"
        STRICT_SAFETY_ENABLED = "true"
        COPILOT_EXE_PATH = "copilot"
        MODEL_ROUTING_TIER1 = "gpt-5.4-mini"
        MODEL_ROUTING_TIER2 = "claude-sonnet-4.6"
        MODEL_ROUTING_TIER3 = "claude-opus-4.7"
        INSTALL_PRESET = "standard"
        PRIMARY_STACK_PACK = "web-app"
        STACK_PACKS_YAML = '["web-app", "api-service", "deployable-service"]'
        INSTALL_LAYERS_YAML = '["foundation", "instructions", "workflow", "review", "runtime", "backlog", "knowledge", "overlays"]'
        CAPABILITY_PACKS_YAML = '["continuous-learning", "strict-safety", "release-observability", "adversarial-review"]'
        HARNESS_OVERRIDES_YAML = "{}"
    }
    tuning_history       = @()
    vscode_settings      = [ordered]@{
        applied            = $false
        user_settings_path = $null
        entries_added      = @()
        skipped_because    = "deferred to operator (run 'autoharness setup-vscode' to apply)"
    }
}

# Convert to JSON then ingest as YAML-compatible (we'll write JSON-style YAML which is valid YAML)
$json = $manifest | ConvertTo-Json -Depth 10
$out = Join-Path $WS '.autoharness/harness-manifest.yaml'
# Write as YAML — JSON is a valid YAML subset, and the schema validator parses YAML.
Set-Content -Path $out -Value $json -Encoding UTF8
Write-Host "Manifest written: $out ($($artifacts.Count) artifacts)"
