# 'Under the hood' blog articles

## Getting started

```shell
virtualenv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Building the blog pages

```shell
pelican -o docs content
```

## Previewing the blog

```shell
pelican --listen
```

