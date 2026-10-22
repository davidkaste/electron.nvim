local M = {}
local state

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf = nil
end

local function render(current)
  if #vim.api.nvim_list_uis() == 0 then
    return
  end
  local width = math.min(64, vim.o.columns - 4)
  local height = math.min(12, vim.o.lines - vim.o.cmdheight - 4)
  if width < 12 or height < 4 then
    close()
    return
  end
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    close()
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = 'wipe'
    vim.bo[state.buf].filetype = 'electron'
    state.win = vim.api.nvim_open_win(state.buf, false, {
      relative = 'editor',
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2) - 1,
      col = math.floor((vim.o.columns - width) / 2),
      style = 'minimal',
      border = 'rounded',
      title = ' electron.nvim ',
      title_pos = 'center',
      focusable = false,
      zindex = 60,
    })
    vim.wo[state.win].wrap = false
  end
  local lines = {
    'Initializing extension host...',
    current and string.format('Loading extension %d/%d: %s', state.loaded + 1, state.total, current)
      or string.format('Extensions processed: %d/%d', state.loaded, state.total),
    '',
  }
  for i = math.max(1, #state.names - height + 6), #state.names do
    lines[#lines + 1] = '[OK] ' .. state.names[i]
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'Your patience is appreciated.'
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.cmd.redraw()
end

local function name_of(spec)
  if type(spec) == 'table' and spec.name then
    return spec.name
  end
  local src = type(spec) == 'table' and spec.src or spec
  return (src:gsub('/+$', ''):match('([^/]+)$') or src):gsub('%.git$', '')
end

function M.disable()
  if not state then
    return
  end
  if vim.pack.add == state.wrapper then
    vim.pack.add = state.original
  end
  vim.api.nvim_del_augroup_by_id(state.group)
  close()
  state.enabled = false
end

function M.setup()
  if state and state.enabled then
    return
  end
  if not vim.pack or type(vim.pack.add) ~= 'function' then
    error('electron.nvim requires Neovim 0.12+ with vim.pack.add()', 2)
  end
  state = {
    enabled = true,
    original = vim.pack.add,
    total = 0,
    loaded = 0,
    names = {},
  }
  state.group = vim.api.nvim_create_augroup('ElectronStartup', { clear = true })
  vim.api.nvim_create_autocmd('VimEnter', {
    group = state.group,
    once = true,
    callback = close,
  })

  state.wrapper = function(specs, opts)
    vim.validate('specs', specs, 'table')
    state.total = state.total + #specs
    local ok, err = pcall(function()
      for _, spec in ipairs(specs) do
        local name = name_of(spec)
        render(name)
        -- Process UI events while deliberately holding up the caller.
        local _, reason = vim.wait(1000)
        if reason == -2 then
          error('electron.nvim loading interrupted')
        end
        state.original({ spec }, opts)
        state.loaded = state.loaded + 1
        state.names[#state.names + 1] = name
        render()
      end
    end)
    if not ok or vim.v.vim_did_enter == 1 then
      close()
    end
    if not ok then
      error(err, 0)
    end
  end
  vim.pack.add = state.wrapper
end

return M
