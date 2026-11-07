#!/bin/bash

#Default to dry-run mode
DRY_RUN=true

echo "Parse command line arguments"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -D) DRY_RUN=false ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

echo "Fetches updates from the remote repo and removes any remote-tracking references that no longer exist on the remote"
git fetch -p
echo "Fetch all remotes to ensure we have latest information"
git fetch --all

echo "Get list of remote branches (strip refs/remotes/origin/ prefix)"
REMOTE_BRANCHES=$(git branch -r | sed 's/origin\///' | tr -d ' ')
echo $REMOTE_BRANCHES
echo ""

echo "Now, process each local branch"
while read -r branch; do
    # Clean branch name (remove leading spaces and asterisk)
    branch_name=$(echo "$branch" | sed 's/^* //;s/^ *//')
    # Set is_current is value has "*"
    is_current=$(echo "$branch" | grep -q "^\*" && echo true || echo false)
    
    [[ -z "$branch_name" ]] && echo "Skip branch because is empty" && continue
    
    [[ "$branch_name" == "develop" || "$branch_name" == "main" ]] && echo "Skip branch because is develop or main" && continue
    
    echo "Check if <$branch_name> exists on remote"
    if ! echo "$REMOTE_BRANCHES" | grep -q "^${branch_name}$"; then
        if [ "$DRY_RUN" = true ]; then
            echo "Would delete branch: <$branch_name>"
        else
            if [ "$is_current" = true ]; then
                echo "Skipping current branch: <$branch_name>"
            else
                echo "Deleting branch: <$branch_name>"
                git branch -D "$branch_name"
            fi
        fi
    else
        echo "Remote branch exists for <$branch_name>. Skip delete."
    fi
done < <(git branch)