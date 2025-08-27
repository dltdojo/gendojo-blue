https://forgejo.org/docs/latest/admin/actions/runner-installation/

# register runner to forgejo

```sh
docker compose up registry -d
bash runner.sh --build

mkdir -p runner-data
chown -R 1000:1000 runner-data
# Get the runner's token from forgejo web ui.
export FORGEJO_RUNNER_TOKEN="MGlqVKv7iOmjYKbswisPxCudgUFD91GeoZySKFz4"
bash runner.sh --register

bash runner.sh --start
```

TODOs

- cache issue.