# nvim
Yet another neovim dotfile repo. 

I'm mid-migration of my unhinged `init.lua` into a more modularized approach. 

(Sometimes) it works on my machine.  

Would not recommend using this as is.... but I'm tired of reading lua so commiting this as a checkpoint.

# Issues
- LSP isn't automatically configured on new machines. 
    - `go install golang.org/x/tools/gopls@latest`
    - `sudo snap install marksman # don't yell at me about snap`
- Fix with `MasonInstall gopls/json-lsp|...` ?
