# Releasing

How to cut a new release of `bridgetown-image-pipeline`. Two paths: **manual** (`rake release` from your machine) and **automated** (push a tag, GitHub Actions publishes via Trusted Publishing).

## Pre-flight checks

Run these before bumping the version:

```sh
bundle exec rake test       # all green
bundle exec rake rubocop    # clean
bundle exec rake build      # gem builds without warnings
```

Optional sanity: unpack the built gem and confirm no stray files shipped.

```sh
gem unpack pkg/bridgetown-image-pipeline-X.Y.Z.gem -t /tmp/unpacked
ls /tmp/unpacked/bridgetown-image-pipeline-X.Y.Z
```

Make sure `.bridgetown-cache/`, fixtures, and test files are not included.

## Version + changelog

1. Bump the constant in [lib/bridgetown/image_pipeline/version.rb](lib/bridgetown/image_pipeline/version.rb).
2. Add a dated section to [CHANGELOG.md](CHANGELOG.md) describing the changes since the last release.
3. Commit both changes together:

   ```sh
   git commit -am "Release vX.Y.Z"
   ```

## Path A — manual release (current default)

`bundler/gem_tasks` (loaded in [Rakefile](Rakefile)) provides `rake release`. It will:

- Build the gem into `pkg/`
- Create a `vX.Y.Z` git tag
- Push the commit and tag to `origin`
- Push the `.gem` to rubygems.org using credentials in `~/.gem/credentials`

```sh
bundle exec rake release
```

Requires `gem signin` to have been run once on this machine. Credentials live at `~/.gem/credentials` (chmod 600).

## Path B — automated release via GitHub Actions

[.github/workflows/release.yml](.github/workflows/release.yml) publishes on any `v*` tag push using rubygems.org Trusted Publishing (OIDC, no stored API key).

**One-time setup** (already done? skip):

1. **rubygems.org** → gem page → Trusted Publishers → add:
   - Repository: `beflagrant/bridgetown-image-pipeline`
   - Workflow filename: `release.yml`
   - Environment: `rubygems`
2. **GitHub** → repo Settings → Environments → create `rubygems`. Optionally restrict to tags matching `v*`.
3. The gem must already exist on rubygems.org (Trusted Publishing won't create a new gem). First release must be a manual `rake release` or `gem push`.

**Release flow once set up:**

```sh
# bump version.rb and CHANGELOG.md
git commit -am "Release vX.Y.Z"
git tag vX.Y.Z
git push origin main --tags
```

The workflow runs tests, then `rubygems/release-gem@v1` builds and pushes. Watch the Actions tab.

> `rubygems/release-gem@v1` expects the gemspec version to match the tag — drift fails loud. That's a feature.

## After publishing

- Confirm the version appears on https://rubygems.org/gems/bridgetown-image-pipeline.
- Smoke test in a clean dir: `gem install bridgetown-image-pipeline -v X.Y.Z` then `ruby -rbridgetown/image_pipeline -e 'puts Bridgetown::ImagePipeline::VERSION'`.
- Close any milestones / linked issues.

## Yanking a broken release

If a release is broken, yank within minutes of publishing rather than letting installs spread:

```sh
gem yank bridgetown-image-pipeline -v X.Y.Z
```

Yanked versions can't be re-pushed under the same number. Bump to `X.Y.Z+1` and release a fix. Note the yank in CHANGELOG.md.

## Notes

- `rake release` and the Action both rely on the gemspec's `files` glob — keep it tight so test fixtures and cache dirs stay out of the published gem.
- Trusted Publishing supersedes the older `RUBYGEMS_API_KEY` secret pattern. Do not add that secret if it isn't already there.
- Pre-release versions (`X.Y.Z.pre1`, `X.Y.Z.rc1`) work the same — tag them `vX.Y.Z.pre1` for the Action to fire.
