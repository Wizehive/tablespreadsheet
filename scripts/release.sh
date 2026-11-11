#!/usr/bin/env bash
#
# Release the Wizehive fork of jspreadsheet-ce (github.com/wizehive/tablespreadsheet).
#
# HOW A CHANGE REACHES MAGPIE
#
#   Magpie installs this repo as "jspreadsheet-ce": "github:wizehive/tablespreadsheet#<tag>", and its
#   npm-shrinkwrap.json pins the exact commit that tag pointed to. Two things follow from that:
#
#     - npm never builds this package. Magpie gets the committed dist/index.js, so dist must be rebuilt
#       and committed with every change to src/.
#     - Merging to master changes nothing in magpie. A change only arrives when it is tagged here and
#       magpie's package.json + npm-shrinkwrap.json are bumped to the new tag.
#
#   Versions are the upstream version plus a fork number: 4.13.2-wizehive.1, 4.13.2-wizehive.2, ...
#   We do not control upstream's version, so the fork number is ours to count.
#
# STEP BY STEP
#
#   The example branch below is fix/my-change; use your own name. Run every command from the root of the
#   repo named in the part's heading.
#
#   PART 1 - tablespreadsheet repo, on your feature branch. Everything here happens BEFORE the PR is merged.
#
#     1. Start from an up-to-date master:
#            git checkout master
#            git pull
#     2. Create your feature branch and stay on it for steps 3-9:
#            git checkout -b fix/my-change
#     3. Make your change in src/index.js. Do not edit dist/ by hand and do not run npm run build;
#        step 6 builds dist for you.
#     4. Install dependencies (first time in this checkout only) and run the tests:
#            npm install
#            npm test
#     5. Commit your change on the feature branch:
#            git add src
#            git commit -m "Describe your change"
#        Leave the working tree clean; prepare refuses to run with uncommitted changes.
#     6. Still on fix/my-change, run:
#            scripts/release.sh prepare
#        This adds one more commit to fix/my-change, "chore(release): v<version>", containing the version
#        bump in package.json and the rebuilt dist/index.js. Your branch now has your commit(s) plus that one.
#     7. Push the feature branch:
#            git push -u origin fix/my-change
#     8. Open the PR from fix/my-change into master:
#            gh pr create -R wizehive/tablespreadsheet --base master --head fix/my-change
#        (-R is required: plain gh in this checkout points at the upstream jspreadsheet/ce repo.)
#     9. Get the PR reviewed and merge it on GitHub.
#
#   PART 2 - tablespreadsheet repo, on master. Everything here happens AFTER the PR is merged.
#
#    10. Switch back to master and pull the merge:
#            git checkout master
#            git pull
#    11. On master, run:
#            scripts/release.sh tag
#        This changes no files and makes no commits. It checks master matches GitHub and the merged dist
#        matches a fresh build, asks for confirmation, then tags the current master commit v<version>
#        and pushes the tag. It prints the npm install line for step 14. Until this runs, magpie cannot
#        get the change.
#    12. Optional: delete the merged feature branch:
#            git branch -d fix/my-change
#
#   PART 3 - magpie repo.
#
#    13. Start a magpie branch from an up-to-date main:
#            git checkout main
#            git pull
#            git checkout -b chore/bump-tablespreadsheet
#    14. Install the new tag (the exact line step 11 printed):
#            npm install "jspreadsheet-ce@github:wizehive/tablespreadsheet#v<version>"
#    15. Check that package.json now ends in #v<version>, and that in npm-shrinkwrap.json the "resolved"
#        value for "node_modules/jspreadsheet-ce" ends in the commit step 11 tagged.
#    16. Commit both files together, push, and open a magpie PR:
#            git add package.json npm-shrinkwrap.json
#            git commit -m "chore(deps): bump jspreadsheet-ce to v<version>"
#            git push -u origin chore/bump-tablespreadsheet
#        The change reaches an environment when that magpie PR is merged and deployed.
#
# OTHER CASES
#
#   Releasing several merged PRs at once:
#       Do Part 1 for each PR but skip step 6, and merge them. Then:
#            git checkout master
#            git pull
#            git checkout -b release/next
#            scripts/release.sh prepare
#            git push -u origin release/next
#            gh pr create -R wizehive/tablespreadsheet --base master --head release/next
#       Merge that PR, then do Part 2 and Part 3.
#
#   Your PR conflicts on package.json because another PR ran prepare and merged first:
#       On your feature branch, drop your release commit, rebase, and run prepare again:
#            git checkout fix/my-change
#            git reset --hard HEAD~1           (removes only your "chore(release)" commit)
#            git pull --rebase origin master
#            scripts/release.sh prepare
#            git push --force-with-lease
#       prepare picks the next number and rebuilds dist with both changes in it.
#
#   Bringing in a newer upstream jspreadsheet/ce version:
#       Merge upstream into a feature branch, then in step 6 pass the upstream version:
#            scripts/release.sh prepare 4.14.0        ->  version 4.14.0-wizehive.1
#
#   Docs-only or test-only change:
#       No release. Do steps 1-5 and 7-9 only; skip step 6 and Parts 2 and 3.
#
#   tag fails with "committed dist does not match a fresh build":
#       Something on master changed src without rebuilding dist. Nothing was tagged. Fix it with a
#       release branch, exactly as in "Releasing several merged PRs at once", then run Part 2 again.
#
# COMMANDS
#
#   scripts/release.sh prepare [version]   Part 1, step 6. On your feature branch, never master.
#                                          No version: bump the fork number.
#   scripts/release.sh tag [--dry-run] [--yes]
#                                          Part 2, step 11. On master after the merge. --dry-run checks
#                                          without tagging; --yes skips the confirmation prompt.
#   scripts/release.sh --help              print this.
#
set -euo pipefail

REPO_SLUG='wizehive/tablespreadsheet'
PACKAGE_NAME='jspreadsheet-ce'
SUFFIX='wizehive'
MAIN_BRANCH='master'
REMOTE='origin'

die() {
	echo "error: $*" >&2
	exit 1
}

info() {
	echo "==> $*"
}

usage() {
	awk 'NR > 2 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
	exit "${1:-0}"
}

cd "$(git rev-parse --show-toplevel)"

current_version() {
	node -p "require('./package.json').version"
}

next_version() {
	local requested="$1" current="$2"
	if [ -n "$requested" ]; then
		requested="${requested#v}"
		case "$requested" in
			*-"$SUFFIX".*) echo "$requested" ;;
			*-*) die "version '$requested' has a prerelease that is not -$SUFFIX.N" ;;
			*) echo "$requested-$SUFFIX.1" ;;
		esac
		return
	fi
	if [[ "$current" =~ ^(.+)-$SUFFIX\.([0-9]+)$ ]]; then
		echo "${BASH_REMATCH[1]}-$SUFFIX.$((BASH_REMATCH[2] + 1))"
	else
		echo "$current-$SUFFIX.1"
	fi
}

validate_version() {
	[[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+-$SUFFIX\.[0-9]+$ ]] || die "'$1' is not in the form X.Y.Z-$SUFFIX.N"
}

remote_tag_exists() {
	git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$1" >/dev/null 2>&1
}

require_clean_tree() {
	[ -z "$(git status --porcelain --untracked-files=no)" ] || die 'working tree has uncommitted changes'
}

ensure_deps() {
	if [ ! -d node_modules ]; then
		info 'installing dependencies'
		npm install --no-audit --no-fund
	fi
}

# npm does not build git dependencies at install time, so the committed dist is what consumers get.
build_dist() {
	ensure_deps
	info 'building dist'
	npm run build --silent >/dev/null
}

prepare() {
	local requested="${1:-}" branch current version
	branch="$(git branch --show-current)"
	[ -n "$branch" ] || die 'not on a branch'
	[ "$branch" != "$MAIN_BRANCH" ] || die "run prepare on a feature branch, not $MAIN_BRANCH; the bump goes through a PR"
	require_clean_tree

	current="$(current_version)"
	version="$(next_version "$requested" "$current")"
	validate_version "$version"
	[ "$version" != "$current" ] || die "package.json is already $version"

	git fetch --quiet --tags "$REMOTE"
	! remote_tag_exists "v$version" || die "tag v$version already exists on $REMOTE"

	info "version $current -> $version"
	npm version "$version" --no-git-tag-version --allow-same-version >/dev/null
	build_dist

	git add package.json dist
	git commit --quiet -m "chore(release): v$version"
	info "committed chore(release): v$version on $branch"
	echo
	echo 'Next (steps 7-11 in scripts/release.sh --help):'
	echo "  git push -u $REMOTE $branch"
	echo "  gh pr create -R $REPO_SLUG --base $MAIN_BRANCH --head $branch"
	echo '  merge the PR on GitHub, then:'
	echo "  git checkout $MAIN_BRANCH && git pull && scripts/release.sh tag"
}

tag() {
	local assume_yes=0 dry_run=0 version tag_name answer
	while [ $# -gt 0 ]; do
		case "$1" in
			--yes | -y) assume_yes=1 ;;
			--dry-run | -n) dry_run=1 ;;
			*) die "unknown option '$1'" ;;
		esac
		shift
	done

	[ "$(git branch --show-current)" = "$MAIN_BRANCH" ] || die "run tag on $MAIN_BRANCH"
	require_clean_tree
	git fetch --quiet --tags "$REMOTE"
	[ "$(git rev-parse HEAD)" = "$(git rev-parse "$REMOTE/$MAIN_BRANCH")" ] ||
		die "$MAIN_BRANCH does not match $REMOTE/$MAIN_BRANCH; pull first"

	version="$(current_version)"
	validate_version "$version"
	tag_name="v$version"
	! remote_tag_exists "$tag_name" || die "tag $tag_name already exists on $REMOTE; run prepare to bump the version"
	! git rev-parse --quiet --verify "refs/tags/$tag_name" >/dev/null ||
		die "local tag $tag_name exists but is not on $REMOTE; delete it (git tag -d $tag_name) and rerun"

	build_dist
	if ! git diff --quiet -- dist; then
		git checkout -- dist
		die "committed dist does not match a fresh build of src; nothing was tagged. See 'tag fails' in scripts/release.sh --help"
	fi
	info 'committed dist matches a fresh build'

	if [ "$dry_run" = 1 ]; then
		info "dry run: would tag $(git rev-parse --short HEAD) as $tag_name and push it to $REMOTE"
		exit 0
	fi

	if [ "$assume_yes" != 1 ]; then
		printf 'Tag %s as %s and push it to %s? [y/N] ' "$(git rev-parse --short HEAD)" "$tag_name" "$REMOTE"
		read -r answer
		case "$answer" in
			y | Y | yes) ;;
			*) die 'aborted' ;;
		esac
	fi

	git tag -a "$tag_name" -m "$tag_name"
	git push --quiet "$REMOTE" "refs/tags/$tag_name"
	info "pushed $tag_name ($(git rev-parse --short HEAD))"
	echo
	echo 'In the consuming repo, set the dependency and reinstall so npm-shrinkwrap.json moves to this commit:'
	echo
	echo "  npm install \"$PACKAGE_NAME@github:$REPO_SLUG#$tag_name\""
	echo
	echo 'Then commit package.json and npm-shrinkwrap.json together.'
}

case "${1:-}" in
	prepare)
		shift
		[ $# -le 1 ] || usage 1
		prepare "${1:-}"
		;;
	tag)
		shift
		tag "$@"
		;;
	-h | --help | help) usage 0 ;;
	*) usage 1 ;;
esac
