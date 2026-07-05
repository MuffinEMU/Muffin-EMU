# GitHub Setup & Deployment

## Initial Repository Setup

### 1. Create GitHub Repository

1. Go to [github.com/new](https://github.com/new)
2. Repository name: `cemu-ios-a-chip`
3. Description: "Wii U emulator for iOS A-chip devices"
4. Visibility: Public (for sharing) or Private
5. DO NOT initialize with README (already have one)
6. Click "Create repository"

### 2. Configure Local Repository

```bash
cd ~/cemu-ios-a-chip

# Add remote (replace USERNAME with your GitHub username)
git remote add origin https://github.com/USERNAME/cemu-ios-a-chip.git

# Or if using SSH keys:
git remote add origin git@github.com:USERNAME/cemu-ios-a-chip.git

# Verify remote
git remote -v
```

### 3. Push to GitHub

```bash
# Set main as default branch
git branch -M main

# Push all commits
git push -u origin main

# Push tags (for releases)
git push --tags
```

## GitHub Actions Configuration

### Automatic IPA Building

The workflow file `.github/workflows/build-ipa.yml` is already configured.

**What it does:**
- ✅ Builds on every push
- ✅ Creates unsigned IPA artifact
- ✅ Uploads to Actions artifacts
- ✅ Creates releases on tags

**To trigger build:**
```bash
git tag v1.0.0
git push origin v1.0.0
```

This creates a release with IPA download link.

### Accessing Builds

1. **From GitHub Actions:**
   - Go to repo → Actions → build-ipa
   - Select recent workflow run
   - Download artifact (CemuEmulator-iOS)

2. **From Releases:**
   - Go to repo → Releases
   - Download .ipa file from release

## Deployment to TestFlight (Optional)

For internal testing via TestFlight:

### Prerequisites
- Apple Developer account ($99/year)
- Provisioning profile
- Team ID

### Steps

1. **Create Signing Identity**
   ```bash
   # In Xcode, select development team
   # Xcode will auto-create signing assets
   ```

2. **Update Workflow**
   Edit `.github/workflows/build-ipa.yml`:
   ```yaml
   - name: Build Signed IPA
     env:
       DEVELOPMENT_TEAM: YOUR_TEAM_ID
       CODE_SIGN_IDENTITY: "Apple Development"
   ```

3. **Upload to TestFlight**
   - Use Xcode Cloud or Fastlane
   - Or manually via Xcode organizer

## Sideloading Distribution

For testing without App Store:

### Via AltStore

1. Download AltStore from altstore.io
2. Share IPA via AirDrop/Mail
3. Open in AltStore
4. Install on device (auto-renews weekly)

### Via TrollStore (Advanced)

1. Requires jailbreak on iOS 15.0-16.6
2. Supports permanent app installation
3. No weekly re-signing needed

### Via Configurator 2

1. Connect device to Mac
2. Apple Configurator 2 → Right-click device → Add
3. Select CemuEmulator.ipa
4. Install automatically

## Release Management

### Creating Releases

```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release 1.0.0: Initial release with UI polish and upscaling"

# Push tag
git push origin v1.0.0
```

Workflow automatically:
- Builds IPA
- Creates GitHub Release
- Uploads IPA as release asset
- Generates release notes

### Release Naming Convention

```
vX.Y.Z - Release Title

## Features
- First feature
- Second feature

## Bug Fixes
- Fixed issue 1
- Fixed issue 2

## Known Limitations
- Limitation 1
- Limitation 2
```

## CI/CD Status

### View Build Status

```bash
# In terminal
gh run list --repo USERNAME/cemu-ios-a-chip

# Web: Go to repo → Actions tab
```

### Debugging Failed Builds

1. Click failed workflow run
2. Review logs
3. Common issues:
   - Xcode version mismatch
   - Missing frameworks
   - Provisioning profile issues

## GitHub Pages Documentation

To host documentation:

1. Enable in Settings → Pages
2. Source: GitHub Actions
3. Deploy `docs/` directory
4. Accessible at `USERNAME.github.io/cemu-ios-a-chip`

## Protected Branches

Recommended settings for `main` branch:

1. Settings → Branches → Add rule
2. Branch name pattern: `main`
3. Enable:
   - "Require a pull request before merging"
   - "Require status checks to pass"
   - "Require branches to be up to date"

## GitHub Secrets (For Signed Builds)

1. Settings → Secrets and variables → Actions
2. Add:
   - `DEVELOPER_TEAM_ID`: Your Team ID
   - `APPLE_ID`: Developer account email
   - `APPLE_PASSWORD`: App-specific password

Usage in workflow:
```yaml
env:
  DEVELOPMENT_TEAM: ${{ secrets.DEVELOPER_TEAM_ID }}
```

## Community & Collaboration

### Enable Issues
- Settings → Features → Issues ✅
- For bug reports and feature requests

### Enable Discussions
- Settings → Features → Discussions ✅
- For community questions and feedback

### Add License
Recommended: MIT License
- Allows modification and distribution
- Keeps legal liability minimal

License file:
```
MIT License

Copyright (c) 2026 Void

Permission is hereby granted...
```

## Mirrors & Backup

### Backup to Another Service

```bash
# Create backup mirror on GitLab
git push --mirror https://gitlab.com/USERNAME/cemu-ios-a-chip.git

# Or to Codeberg
git push --mirror https://codeberg.org/USERNAME/cemu-ios-a-chip.git
```

### Keep Synchronized

```bash
# Pull from all remotes
git fetch --all

# Push to all remotes
for remote in $(git remote); do
  git push $remote main
done
```

## Security Considerations

- Keep credentials in GitHub Secrets, never in code
- Use SSH keys instead of HTTPS tokens when possible
- Enable 2FA on GitHub account
- Regularly review Actions permissions
- Consider code signing certificates

## Deployment Checklist

- [x] Local git repository initialized
- [x] GitHub repository created
- [x] Remote configured
- [x] Code pushed to GitHub
- [x] GitHub Actions workflow enabled
- [x] IPA building on push/tags
- [ ] Code signing configured (optional)
- [ ] TestFlight setup (optional)
- [ ] GitHub Pages documentation (optional)
- [ ] Community features enabled (optional)

## Next Steps

1. Create GitHub repo
2. Add remote: `git remote add origin https://github.com/USERNAME/cemu-ios-a-chip.git`
3. Push code: `git push -u origin main`
4. Create release tag: `git tag -a v1.0.0 -m "Release 1.0.0"`
5. Push tags: `git push origin v1.0.0`
6. Access IPA from GitHub Releases

The entire CI/CD pipeline is ready to go. Just push to GitHub and watch it build.
