function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Step,

        [Parameter(Mandatory = $true)]
        [string] $Title
    )

    Write-Host ""
    Write-Host ("[{0}] {1}" -f $Step, $Title) -ForegroundColor Cyan
    Write-Host ""
}

function Write-InfoLine {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host ("[INFO] {0}" -f $Message) -ForegroundColor Gray
}

function Write-SuccessLine {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host ("[ OK ] {0}" -f $Message) -ForegroundColor Green
}

function Write-WarnLine {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host ("[WARN] {0}" -f $Message) -ForegroundColor Yellow
}

function Write-FailLine {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host ("[FAIL] {0}" -f $Message) -ForegroundColor Red
}

function Write-InstallStart {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    Write-Host ""
    Write-Host "[INFO] Installing " -NoNewline -ForegroundColor Gray
    Write-Host $Name -ForegroundColor Cyan
}
