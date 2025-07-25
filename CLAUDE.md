# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MOSSU (Mercadona Online Slack Status Updater) is a macOS status bar application that automatically updates your Slack status based on Wi-Fi network or location. The project consists of:

- **macOS App**: Swift-based status bar application (`MOSSU macos/`)
- **Backend**: Node.js serverless functions for Slack OAuth (`api/`)
- **Distribution**: Automated build and deployment scripts (`deploy.sh`, `public/`)

## Build and Development Commands

### macOS Application
```bash
# Open the project in Xcode
open "MOSSU.xcodeproj"

# Build and archive for distribution
./deploy.sh

# Run tests
xcodebuild -scheme "MOSSU" -configuration Debug test
```

### Backend (Node.js)
```bash
# Install dependencies
npm install

# Run tests
npm test
```

## Architecture

### Core Components

**AppDelegate.swift**: Main application controller that handles:
- OAuth URL scheme handling (`mossu://oauth`)
- Status bar menu management
- Slack authentication flow coordination

**SlackStatusManager.swift**: Core business logic for:
- Wi-Fi network monitoring
- Slack API integration
- Location-based office detection
- Status update automation

**StatusBarController.swift**: UI management for macOS status bar icon and menu

**Office.swift**: Data models for office locations and Wi-Fi mapping

### Authentication Flow
1. User clicks auth in menu → Opens Slack OAuth in browser
2. Slack redirects to backend (`api/slack/oauth/callback.js`)
3. Backend exchanges code for token, redirects to `mossu://oauth?token=...`
4. macOS app receives URL scheme, stores token, starts tracking

### Key Configuration
- **Constants.swift**: Contains Slack client ID and OAuth settings
- **Environment Variables** (backend):
  - `SLACK_CLIENT_ID`
  - `SLACK_CLIENT_SECRET` 
  - `SLACK_REDIRECT_URI`
  - `FRONTEND_URL`

## Development Notes

- The app uses Sparkle framework for automatic updates
- OAuth tokens are stored in UserDefaults with key "token"
- Logs are managed through LogManager.swift with in-memory storage
- Wi-Fi detection happens through Reachability.swift
- The app runs as an accessory (no dock icon) after initial launch

## Deployment

The `deploy.sh` script handles the complete build and distribution process:
- Increments version numbers automatically
- Creates signed macOS archive
- Generates ZIP for Sparkle updates
- Updates appcast.xml for auto-updater
- Commits and pushes to git repository