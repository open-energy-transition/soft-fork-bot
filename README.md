# soft-fork-bot

A GitLab bot to keep a soft fork compatible with its upstream repository.

A soft fork is a (often private) long-running fork of a (usually open source) repository. For more details and some strategies on how to maintain soft forks, see:
[Being friendly: Strategies for friendly fork management - The GitHub Blog](https://github.blog/2022-05-02-friend-zone-strategies-friendly-fork-management/)

This bot assumes the soft fork is using the simple Merge Strategy. The bot runs on a schedule and checks if the upstream repository has any new changes, and if so, it opens a pull/merge request to merge those changes into the fork. Any conflicts must be resolved manually before the PR/MR is merged.

## Installation

### GitLab setup:

- Add the following stage and job to `.gitlab-ci.yml`, substituting `[things in brackets]` with the appropriate values for your setup:
  ```yml
  stages:
    - merge-upstream-changes
    ...

  merge_upstream_changes:
    stage: merge-upstream-changes
    rules:
      - if: '$CI_COMMIT_BRANCH != $CI_DEFAULT_BRANCH'
        when: never
      - if: $CI_PIPELINE_SOURCE == "schedule"
        when: always
    image: debian:bookworm-slim
    variables:
      GIT_STRATEGY: clone
      # GIT_DEPTH: 1 # TODO if this job gets slow experiment with fetching less
      UPSTREAM_REPO: [URL of upstream repo e.g. "https://github.com/PyPSA/pypsa-eur"]
      UPSTREAM_BRANCH: [main or master]
      THIS_REPO: [URL of soft fork repo e.g. "https://gitlab.com/PyPSA/pypsa-eur-fork"]
      CHANGE_BRANCH: [name of branch bringing in upstream's changes e.g. "upstream_changes"]
      HOST: $CI_PROJECT_URL
      CI_PROJECT_ID: $CI_PROJECT_ID
      GITLAB_USER: $GITLAB_USER
      PRIVATE_TOKEN: $GITLAB_ACCESS_TOKEN
    before_script:
      - apt-get update -qy
      - apt-get install -y git curl
    script:
      - export MAIN_BRANCH=${CI_DEFAULT_BRANCH:-main}
      - curl -fsSL https://github.com/open-energy-transition/soft-fork-bot/raw/main/merge_upstream_changes.sh -o merge_upstream_changes.sh
      - /bin/bash merge_upstream_changes.sh
  ```
- Go to Settings > Access Tokens and create a new token with role Developer and scopes `api, write_repository`
- Go to Settings > CI/CD and add variables GITLAB_USER and GITLAB_ACCESS_TOKEN (masked and protected)
- Go to CI/CD > Schedules and add a new schedule to run the pipeline on the default branch.
  Add the following to the rules of every other job so that no other job runs on schedule:
  ```yml
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
      when: never
  ```

## Roadmap / feature wishlist

- [ ] Add support for GitHub repositories
- [ ] Assign MR to maintainer
- [ ] If no work on pre-existing MR then update and force push

## Contributors

- [Siddharth Krishna](https://github.com/siddharth-krishna) (maintainer)
- [Dhanshree Arora](https://github.com/DhanshreeA)
