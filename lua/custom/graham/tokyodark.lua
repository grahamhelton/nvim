return {
  {
    'tiagovla/tokyodark.nvim',
    priority = 1000,
    lazy = false,
    config = function()
      require('tokyodark').setup {
        transparent_background = true,
      }
      vim.cmd.colorscheme 'tokyodark'
    end,
  },
}
