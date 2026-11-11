<#
 番茄钟 (tomato_timer) · Windows 桌面版打包脚本
 -------------------------------------------------------------
 前置：Flutter SDK 已加入系统 PATH（flutter --version 可正常输出）
 用法（在 tomato_timer 目录下用 PowerShell 运行）：
   .\build_windows.ps1                      # 用 pubspec.yaml 当前版本号直接构建
   .\build_windows.ps1 -Version 0.4.0+5    # 先写入版本号再构建
   .\build_windows.ps1 -NoGet               # 跳过 flutter pub get（已取过依赖时）
 -------------------------------------------------------------
#>
param(
  [string]$Version = "",
  [switch]$NoGet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $root

# 可选：更新 pubspec.yaml 中的版本号（version: name+build）
if ($Version -ne "") {
  $pubspec = Join-Path $root "pubspec.yaml"
  if (Test-Path $pubspec) {
    (Get-Content $pubspec) -replace '^version:\s*.*$', "version: $Version" | Set-Content $pubspec
    Write-Host "[版本] 已设置 version: $Version" -ForegroundColor Cyan
  } else {
    Write-Warning "未找到 pubspec.yaml，已跳过版本号设置"
  }
}

if (-not $NoGet) {
  Write-Host "[步骤] flutter pub get" -ForegroundColor Cyan
  flutter pub get
}

Write-Host "[步骤] flutter build windows --release" -ForegroundColor Cyan
flutter build windows --release

Write-Host ""
Write-Host "Windows 构建完成 ✅" -ForegroundColor Green
Write-Host "产物目录 : $root\build\windows\x64\runner\Release\" -ForegroundColor Yellow
Write-Host "可执行   : $root\build\windows\x64\runner\Release\tomato_timer.exe" -ForegroundColor Yellow
