" stdpath('data') is where install-nvim.sh puts vim-plug too, so both follow
" XDG_DATA_HOME when it is set instead of assuming ~/.local/share.
call plug#begin(stdpath('data') . '/plugged')
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'OXY2DEV/markview.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'folke/todo-comments.nvim'
Plug 'tomasiser/vim-code-dark'
call plug#end()

set termguicolors
set mouse=a
set number
set title
set textwidth=0
set encoding=utf-8
set ruler
set formatoptions+=o
set showmatch
set incsearch
set hlsearch
set ignorecase
set smartcase
set autoindent
set expandtab
set tabstop=2
set shiftwidth=2

filetype plugin indent on
set background=dark
silent! colorscheme codedark

luafile ~/.config/nvim/plugins.lua
luafile ~/.config/nvim/format.lua

" :Format is the real command (Vim requires a capital); allow typing :format too
cnoreabbrev <expr> format (getcmdtype() ==# ':' && getcmdline() ==# 'format') ? 'Format' : 'format'

autocmd BufRead,BufNewFile *bashrc* set filetype=bash

