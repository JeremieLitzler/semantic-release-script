#!/usr/bin/env bats
#
# Resuming a half-published release: a version tag the target carries, origin
# holds, and GitHub has no release for. The run that left it there died between
# pushing the tag and creating the release, and a re-run used to dead-end on
# the range with no commit in it that the tag makes of its own commit.

load helpers/common

setup() {
  setup_fixture
  tag_version v1.0.0
  given_issue 1 "Export the orders as CSV"
  commit_change "feat: export the orders as CSV (#1)"
}

# half_publish — what the run that died left behind: v1.1.0 on origin, tagged
# on the commit the release was cut from, and no GitHub release carrying it.
half_publish() {
  tag_version v1.1.0
  push_fixture
}

@test "a tag on origin with no release is resumed at step 4 instead of computing a version" {
  half_publish

  run_release

  assert_success
  assert_line --partial "v1.1.0 is on origin with no GitHub release"
  assert_line "== Step 1 — resume the half-published v1.1.0 =="
  assert_line "Version         : 1.1.0 (read off v1.1.0, which origin already holds)"
  refute_line --partial "Bump            :"
  assert_line "Released v1.1.0"

  run gh_calls
  assert_line --regexp '^release create v1\.1\.0 --repo fixture-owner/fixture-repo --title v1\.1\.0 --notes-file .+ --verify-tag$'
}

@test "a resumed release rebuilds the notes over the range its tag was cut on" {
  half_publish

  run_release

  assert_success
  assert_line "Commit range    : v1.0.0..HEAD (last tag: v1.0.0)"
  assert_line "Commits scanned : 1"

  run cat "$(published_notes_file v1.1.0)"
  assert_output "$(printf '### Features\n\n- Export the orders as CSV (#1)\n')"
}

@test "a resume creates no tag: the one on origin is the one published" {
  half_publish

  run_release

  assert_success
  assert_line "== Step 3 — v1.1.0 is already on origin =="
  assert_line --partial "[resume] the tag was pushed before the release that never happened"
  refute_line --partial "Tag v1.1.0 created on"
  refute_line --partial "Tag v1.1.0 pushed to origin."
  refute_local_tag v1.1.1
  refute_remote_tag v1.1.1
}

@test "a resume gates step 4 and nothing else: step 3 writes nothing to hold back" {
  half_publish

  run_release

  assert_success
  assert_line --partial "Continue to step 2 and build the release notes for v1.1.0? (auto-confirmed with --yes)"
  assert_line --partial "Continue to step 4 and publish the GitHub release v1.1.0? (auto-confirmed with --yes)"
  refute_line --partial "Continue to step 3"
}

@test "a tag GitHub already has a release for is not resumed: there is nothing to release" {
  half_publish
  given_release v1.1.0

  run_release

  assert_failure 2
  assert_output --partial "no commit to release in range 'v1.1.0..HEAD'"
  refute_gh_call "release create"
}

@test "a tag only the machine holds is not resumed: it was never pushed" {
  tag_version v1.1.0
  git push -q origin main

  run_release

  assert_failure 2
  assert_output --partial "no commit to release in range 'v1.1.0..HEAD'"
  refute_gh_call "release create"
}

@test "--since narrows the range a resume rebuilds the notes over" {
  given_issue 2 "Keep the cart total in sync"
  commit_change "fix: keep the cart total in sync (#2)"
  half_publish

  run_release --since HEAD~1

  assert_success
  assert_line "Commit range    : HEAD~1..HEAD (last tag: HEAD~1)"
  assert_line "Commits scanned : 1"

  run cat "$(published_notes_file v1.1.0)"
  assert_output "$(printf '### Bug fixes\n\n- Keep the cart total in sync (#2)\n')"
}

@test "--to resumes the half-published release on that commit" {
  half_publish
  commit_change "fix: keep the cart total in sync"
  push_fixture

  run_release --to v1.1.0

  assert_success
  assert_line "== Step 1 — resume the half-published v1.1.0 =="
  assert_line "Target ref      : v1.1.0 (the tag is there, not on HEAD)"
  assert_line "Commit range    : v1.0.0..v1.1.0 (last tag: v1.0.0)"
  assert_line "Released v1.1.0"
}

@test "--dry-run previews the resume and publishes nothing" {
  half_publish

  run_release --dry-run

  assert_success
  assert_line --partial "v1.1.0 is on origin with no GitHub release"
  assert_line "[dry-run] v1.1.0 is already on origin: a real run would publish its release"
  refute_line --partial "[dry-run] no tag was pushed"
  assert_no_release_created
}

@test "--local resumes nothing to the remote: the tag is there and the release is not created" {
  half_publish

  run_release --local

  assert_success
  assert_line "[local] v1.1.0 is on origin, but --local creates no release"
  assert_no_release_created
}

@test "--level is ignored on a resume: the tag already carries the version" {
  half_publish

  run_release --level major

  assert_success
  assert_output --partial "--level is ignored on a resume: v1.1.0 already carries the version"
  assert_line "Released v1.1.0"
}

# The guards weigh on a resume as they do on a release being cut, and the
# containment one runs before the run is recognised as a resume at all. The tag
# is stranded either way; publishing its notes would only add to what has to be
# unpicked once the trunk is put right.
@test "a half-published tag the trunk cannot reach is refused, not resumed" {
  # origin/main stops at v1.0.0, so HEAD sits on a commit the trunk cannot
  # reach — what a run cutting a new tag there would be refused over.
  git push -q origin "v1.0.0^{commit}:refs/heads/main"
  git push -q origin refs/tags/v1.0.0
  tag_version v1.1.0
  push_tag_fixture v1.1.0

  run_release

  assert_failure 3
  assert_output --partial "origin/main does not contain HEAD"
  refute_output --partial "resuming it at step 4"
  assert_no_release_created
}
