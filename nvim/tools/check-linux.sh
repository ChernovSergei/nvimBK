#!/bin/sh
# Run inside the Linux/proot guest. Reports dependencies; changes nothing.
printf 'WordVim Linux/proot dependency check\n'
uname -sm
for tool in nvim git pandoc pwsh java node npm rg cc python3; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-24s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '%-24s MISSING\n' "$tool"
  fi
done
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import PIL; print("Pillow:", PIL.__version__)' || printf 'Pillow MISSING (python3-pil)\n'
fi
for tool in termux-clipboard-get termux-clipboard-set wl-copy wl-paste xclip; do
  command -v "$tool" 2>/dev/null || :
done
printf '\nInside Neovim: :WordHealth and :checkhealth\n'
