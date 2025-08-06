local svdrm = {}

local tx = require 'textentry'
local mu = require 'musicutil'
local md = require 'core/mods'

local NUM_VOICES = 8
local NUM_PERF_SLOTS = 2

local preset_path = "/home/we/dust/data/sidvagn/drmfm_kits"
local default_kit = "/home/we/dust/data/sidvagn/drmfm_kits/default.kit"
local failsafe_kit = "/home/we/dust/code/sidvagn/data/drmfm_kits/default.kit"

local selected_voice = 1
local current_kit = ""
local glb_level = 1
local perf_amt = 0
local perf_names = {"A", "B"}

local perfclock = nil
local perftime = 8 -- beats
local perf_slot = 1

local clipboard = {}

local ratio_options = {}
local ratio_values = {}

-- param list indexing needs to correspond to sc msg!
local param_list = {
  "freq", "tune", "decay", "sweep_time", "sweep_depth", "mod_ratio", "mod_time", "mod_amp", "mod_fb", "mod_dest",
  "noise_amp", "noise_decay", "cutoff_lpf", "cutoff_hpf", "phase", "fold", "level", "pan", "sendA", "sendB"
}

local voice_params = {
  "freq", "tune", "decay", "decay_mod", "sweep_time", "sweep_depth", "mod_ratio", "mod_time", "mod_amp", "mod_fb", "mod_dest",
  "noise_amp", "noise_decay", "cutoff_lpf", "cutoff_hpf", "phase", "fold", "level", "pan", "sendA", "sendB", "perf_mod"
}

local perf_params = {
  "sendA", "sendB", "sweep_time", "sweep_depth", "decay", "mod_time", "mod_amp", "mod_fb", "mod_dest", 
  "noise_amp", "noise_decay", "fold", "cutoff_lpf", "cutoff_hpf"
}

local d_prm = {}
for i = 1, NUM_VOICES do
  d_prm[i] = {}
  d_prm[i].d_mod = 0
  d_prm[i].p_mod = true
  for j = 1, #param_list do
    d_prm[i][j] = 0
  end
end

local dv = {}
dv.min = {}
dv.max = {}
dv.mod = {}
for i = 1, #param_list do
  dv.min[i] = 0
  dv.max[i] = 0
end
for i = 1, NUM_PERF_SLOTS do
  dv.mod[i] = {}
  for j = 1, #param_list do
    dv.mod[i][j] = 0
  end
end
  
local function round_form(param, quant, form)
  return(util.round(param, quant)..form)
end

local function pan_display(param)
  if param < -0.01 then
    return ("L < "..math.abs(util.round(param * 100, 1)))
  elseif param > 0.01 then
    return (math.abs(util.round(param * 100, 1)).." > R")
  else
    return "> <"
  end
end

local function build_menu(dest)
  if dest == "voice" then
    -- voice params
    for i = 1, NUM_VOICES do
      for _,v in ipairs(voice_params) do
        local name = "drmfm_"..v.."_"..i
        if i == selected_voice then
          params:show(name)
          if not md.is_loaded("fx") then
            params:hide("drmfm_sendA_"..i)
            params:hide("drmfm_sendB_"..i)
          end
        else
          params:hide(name)
        end
      end
    end
  elseif dest == "perf" then
    -- perf params
    for i = 1, NUM_PERF_SLOTS do
      for _,v in ipairs(perf_params) do
        local name = "drmfm_"..v.."_perf_"..i
        if i == perf_slot then
          params:show(name)
          params:show("drmfm_perf_depth"..i)
          if not md.is_loaded("fx") then
            params:hide("drmfm_sendA_perf_"..i)
            params:hide("drmfm_sendB_perf_"..i)
          end
        else
          params:hide(name)
          params:hide("drmfm_perf_depth"..i)
        end
      end
    end
  end
  _menu.rebuild_params()
end

local function build_tables()
  for i = 1, 32 do
    local num = 33 - i
    local str = tostring(num)..":1"
    table.insert(ratio_options, str)
  end
  for i = 2, 10 do
    local str = "1:"..tostring(i)
    table.insert(ratio_options, str)
  end
  for i = 1, 32 do
    local num = 33 - i
    table.insert(ratio_values, num)
  end
  for i = 2, 10 do
    local num = 1 / i
    table.insert(ratio_values, num)
  end
end

local function populate_minmax_values()
  for k, v in ipairs(param_list) do
    local p = params:lookup_param("drmfm_"..v.."_1")
    if p.t == 1 then -- number
      dv.min[k] = p.min
      dv.max[k] = p.max
    elseif p.t == 2 then -- option
      dv.min[k] = 1
      dv.max[k] = p.count
    elseif p.t == 3 then -- controlspec
      dv.min[k] = p.controlspec.minval
      dv.max[k] = p.controlspec.maxval
    end
  end
end

local function scale_perf_val(i, k, mult)
  if (param_list[k] == "cutoff_lpf" or param_list[k] == "cutoff_hpf") then
    dv.mod[i][k] = util.linexp(0, 1, dv.min[k], dv.max[k], math.abs(mult)) * (mult < 0 and -1 or 1)
  else
    dv.mod[i][k] = (dv.max[k] - dv.min[k]) * mult
  end
end

local function save_drmfm_kit(txt)
  if txt then
    local kit = {}
    kit.vox = {}
    for _, v in ipairs(voice_params) do
      kit.vox[v] = {}
      for n = 1, NUM_VOICES do
        table.insert(kit.vox[v], params:get("drmfm_"..v.."_"..n))
      end
    end
    kit.mod = {}
    for _, v in ipairs(perf_params) do
      kit.mod[v] = {}
      for n = 1, NUM_PERF_SLOTS do
        table.insert(kit.mod[v], params:get("drmfm_"..v.."_perf_"..n))
      end
    end
    tab.save(kit, preset_path.."/"..txt..".kit")
    current_kit = txt
    params:set("drmfm_load_kit", preset_path.."/"..txt..".kit", true)
    print("saved kit "..preset_path.."/"..txt..".kit")
  end
end

local function load_drmfm_kit(path)
  if path ~= "cancel" and path ~= "" then
    if path:match("^.+(%..+)$") == ".kit" then
      local kit = tab.load(path)
      if kit ~= nil then
        for i, v in ipairs(voice_params) do
          if kit.vox[v] ~= nil then
            for n = 1, NUM_VOICES do
              params:set("drmfm_"..v.."_"..n, kit.vox[v][n])
            end
          end
        end
        for i, v in ipairs(perf_params) do
          for n = 1, NUM_PERF_SLOTS do
            params:set("drmfm_"..v.."_perf_"..n, kit.mod[v][n])
          end
        end
        local name = path:match("[^/]*$")
        current_kit = name:gsub(".kit", "")
        print("load drmfm kit: "..name)
      else
        if util.file_exists(failsafe_kit) then
          load_drmfm_kit(failsafe_kit)
        end
        print("error: could not find kit", path)
      end
    else
      print("error: not a kit file")
    end
  end
end

local function copy_voice(voice)
  local voice = voice or selected_voice
  for _,v in ipairs(param_list) do 
    clipboard[v] = params:get("drmfm_"..v.."_"..voice)
  end
end

local function paste_voice(voice)
  local voice = voice or selected_voice
  for _,v in ipairs(param_list) do 
    params:set("drmfm_"..v.."_"..voice , clipboard[v])
  end
end

function svdrm.drmf_perf(action, slot, bar_val)
  if action == "on" then
    params:set("drmfm_perf_slot", slot)
    if perfclock ~= nil then
      clock.cancel(perfclock)
    end
    perfclock = clock.run(function()
      local counter = 0
      local inc = perftime * bar_val
      local d = 100 / inc
      while counter < perftime do
        params:delta("drmfm_perf_amt", d)
        counter = counter + 1/4
        clock.sync(1/4)
      end 
    end)
  else
    if perfclock ~= nil then
      clock.cancel(perfclock)
    end
    params:set("drmfm_perf_amt", 0)
  end
end

function svdrm.trig(voice, vel)
  local vel = vel and util.linlin(0, 127, 0, 1, vel) or 1
  local msg = {}
  for k, v in ipairs(d_prm[voice]) do
    msg[k] = v
    if param_list[k] == "decay" then
      msg[k] = msg[k] + math.random() * d_prm[voice].d_mod
    elseif param_list[k] == "level" then
      msg[k] = msg[k] * glb_level * vel
    end
    if d_prm[voice].p_mod then
      msg[k] = util.clamp(msg[k] + (dv.mod[perf_slot][k] * perf_amt), dv.min[k], dv.max[k])
    end
  end
  local slot = (voice - 1) -- sc is zero-indexed!
  table.insert(msg, 1, slot)
  osc.send({'localhost',57120}, '/svdrm/trig', msg)
end

function svdrm.add_params()
  -- make directory and copy files
  if util.file_exists(preset_path) == false then
    util.make_dir(preset_path)
    os.execute('cp '.. '/home/we/dust/code/sidvagn/data/drmfm_kits/*.kit '.. preset_path)
  end
  -- populate tables
  build_tables()

  -- svdrm params
  params:add_group("drmfm_params", "drmFM", ((NUM_VOICES * 22) + (NUM_PERF_SLOTS * 15) + 14))

  params:add_separator("drmfm_kits", "drmFM kit")

  params:add_file("drmfm_load_kit", ">> load", default_kit)
  params:set_action("drmfm_load_kit", function(path) load_drmfm_kit(path) end)

  params:add_trigger("drmfm_save_kit", "<< save")
  params:set_action("drmfm_save_kit", function() tx.enter(save_drmfm_kit, current_kit)  end)
   
  params:add_separator("drmfm_settings", "drmFM settings")

  params:add_control("drmfm_global_level", "main level", controlspec.new(0, 1, "lin", 0, 1), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("drmfm_global_level", function(val) glb_level = val end)

  params:add_binary("drmfm_copy_params", "> copy voice", "trigger")
  params:set_action("drmfm_copy_params", function() copy_voice() end)

  params:add_binary("drmfm_paste_params", "< paste voice", "trigger")
  params:set_action("drmfm_paste_params", function() paste_voice() end)

  params:add_separator("drmfm_voice", "voice")

  params:add_number("drmfm_selected_voice", "selected voice", 1, NUM_VOICES, 1)
  params:set_action("drmfm_selected_voice", function(t) selected_voice = t build_menu("voice") end)
  
  params:add_binary("drmfm_trig", "trig voice >>")
  params:set_action("drmfm_trig", function() svdrm.trig(selected_voice) end)
  
  for i = 1, NUM_VOICES do
    params:add_control("drmfm_level_"..i, "level", controlspec.new(0, 2, "lin", 0, 1), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_level_"..i, function(val) d_prm[i][tab.key(param_list, "level")] = val end)

    params:add_control("drmfm_pan_"..i, "pan", controlspec.new(-1, 1, "lin", 0, 0), function(param) return pan_display(param:get()) end)
    params:set_action("drmfm_pan_"..i, function(val) d_prm[i][tab.key(param_list, "pan")] = val end)

    params:add_control("drmfm_sendA_"..i, "send a", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_sendA_"..i, function(val) d_prm[i][tab.key(param_list, "sendA")] = val end)

    params:add_control("drmfm_sendB_"..i, "send b", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_sendB_"..i, function(val) d_prm[i][tab.key(param_list, "sendB")] = val end)
    
    params:add_number("drmfm_freq_"..i, "pitch", 12, 119, 24, function(param) return mu.note_num_to_name(param:get(), true) end)
    params:set_action("drmfm_freq_"..i, function(val) d_prm[i][tab.key(param_list, "freq")] = val end)

    params:add_control("drmfm_tune_"..i, "tune", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "ct") end)
    params:set_action("drmfm_tune_"..i, function(val) d_prm[i][tab.key(param_list, "tune")] = val end)
    
    params:add_control("drmfm_sweep_time_"..i, "sweep time", controlspec.new(0, 1, "lin", 0, 0.1), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_sweep_time_"..i, function(val) d_prm[i][tab.key(param_list, "sweep_time")] = val end)
  
    params:add_control("drmfm_sweep_depth_"..i, "sweep depth", controlspec.new(-1, 1, "lin", 0, 0.02), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_sweep_depth_"..i, function(val) d_prm[i][tab.key(param_list, "sweep_depth")] = val end)

    params:add_control("drmfm_decay_"..i, "decay", controlspec.new(0.01, 4, "lin", 0, 0.2), function(param) return round_form(param:get(), 0.01, "s") end)
    params:set_action("drmfm_decay_"..i, function(val) d_prm[i][tab.key(param_list, "decay")] = val end)

    params:add_control("drmfm_decay_mod_"..i, "decay s&h", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_decay_mod_"..i, function(val) d_prm[i].d_mod = val end)
  
    params:add_control("drmfm_mod_time_"..i, "mod time", controlspec.new(0, 2, "lin", 0, 0.1), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_mod_time_"..i, function(val) d_prm[i][tab.key(param_list, "mod_time")] = val end)
  
    params:add_control("drmfm_mod_amp_"..i, "mod amp", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_mod_amp_"..i, function(val) d_prm[i][tab.key(param_list, "mod_amp")] = val end)
  
    params:add_option("drmfm_mod_ratio_"..i, "mod ratio", ratio_options, 32)
    params:set_action("drmfm_mod_ratio_"..i, function(idx) d_prm[i][tab.key(param_list, "mod_ratio")] = ratio_values[idx] end)
  
    params:add_control("drmfm_mod_fb_"..i, "mod feedback", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_mod_fb_"..i, function(val) d_prm[i][tab.key(param_list, "mod_fb")] = val end)
  
    params:add_control("drmfm_mod_dest_"..i, "mod dest [mix/car]", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(100 - (param:get() * 100), 1, "/")..round_form(param:get() * 100, 1, "") end)
    params:set_action("drmfm_mod_dest_"..i, function(val) d_prm[i][tab.key(param_list, "mod_dest")] = val end)
  
    params:add_control("drmfm_noise_amp_"..i, "noise level", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_noise_amp_"..i, function(val) d_prm[i][tab.key(param_list, "noise_amp")] = val end)
  
    params:add_control("drmfm_noise_decay_"..i, "noise decay", controlspec.new(0.01, 4, "lin", 0, 0.2), function(param) return round_form(param:get(), 0.01, "s") end)
    params:set_action("drmfm_noise_decay_"..i, function(val) d_prm[i][tab.key(param_list, "noise_decay")] = val end)

    params:add_option("drmfm_phase_"..i, "phase", {"0°", "90°"}, 1)
    params:set_action("drmfm_phase_"..i, function(mode) d_prm[i][tab.key(param_list, "phase")] = mode - 1 end)
  
    params:add_control("drmfm_fold_"..i, "wavefold", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_fold_"..i, function(val) d_prm[i][tab.key(param_list, "fold")] = val end)
  
    params:add_control("drmfm_cutoff_lpf_"..i, "cutoff lpf", controlspec.new(20, 18000, "exp", 0, 18000), function(param) return round_form(param:get(), 1, "hz") end)
    params:set_action("drmfm_cutoff_lpf_"..i, function(val) d_prm[i][tab.key(param_list, "cutoff_lpf")] = val end)
  
    params:add_control("drmfm_cutoff_hpf_"..i, "cutoff hpf", controlspec.new(20, 18000, "exp", 0, 20), function(param) return round_form(param:get(), 1, "hz") end)
    params:set_action("drmfm_cutoff_hpf_"..i, function(val) d_prm[i][tab.key(param_list, "cutoff_hpf")] = val end)

    params:add_option("drmfm_perf_mod_"..i, "macros", {"ignore", "follow"}, 2)
    params:set_action("drmfm_perf_mod_"..i, function(mode) d_prm[i].p_mod = mode == 2 and true or false end)
  end

  populate_minmax_values()

  params:add_separator("drmfm_performace_marco", "macro settings")

  params:add_control("drmfm_perf_amt", "perf macro", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("drmfm_perf_amt", function(val) perf_amt = val end)

  params:add_option("drmfm_perf_slot", "perf macro", perf_names, 1)
  params:set_action("drmfm_perf_slot", function(t) perf_slot = t build_menu("perf") end)

  params:add_number("drmfm_perf_time", "perf time", 1, 8, 2, function(param) local name = param:get() == 1 and "bar" or "bars" return param:get().." "..name end)
  params:set_action("drmfm_perf_time", function(val) perftime = val * 4 end)

  for i = 1, NUM_PERF_SLOTS do
    params:add_separator("drmfm_perf_depth"..i, "macro "..perf_names[i])

    params:add_control("drmfm_sendA_perf_"..i, "send a", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_sendA_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "sendA"), val) end)

    params:add_control("drmfm_sendB_perf_"..i, "send b", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_sendB_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "sendB"), val) end)
      
    params:add_control("drmfm_sweep_time_perf_"..i, "sweep time", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_sweep_time_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "sweep_time"), val) end)

    params:add_control("drmfm_sweep_depth_perf_"..i, "sweep depth", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_sweep_depth_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "sweep_depth"), val) end)

    params:add_control("drmfm_decay_perf_"..i, "decay", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_decay_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "decay"), val) end)

    params:add_control("drmfm_mod_time_perf_"..i, "mod time", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_mod_time_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "mod_time"), val) end)

    params:add_control("drmfm_mod_amp_perf_"..i, "mod amp", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_mod_amp_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "mod_amp"), val) end)

    params:add_control("drmfm_mod_fb_perf_"..i, "mod feedback", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_mod_fb_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "mod_fb"), val) end)

    params:add_control("drmfm_mod_dest_perf_"..i, "mod dest [mix/car]", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_mod_dest_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "mod_dest"), val) end)

    params:add_control("drmfm_noise_amp_perf_"..i, "noise level", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_noise_amp_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "noise_amp"), val)end)

    params:add_control("drmfm_noise_decay_perf_"..i, "noise decay", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_noise_decay_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "noise_decay"), val) end)

    params:add_control("drmfm_fold_perf_"..i, "wavefold", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_fold_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "fold"), val) end)

    params:add_control("drmfm_cutoff_lpf_perf_"..i, "cutoff lpf", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_cutoff_lpf_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "cutoff_lpf"), val) end)

    params:add_control("drmfm_cutoff_hpf_perf_"..i, "cutoff hpf", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
    params:set_action("drmfm_cutoff_hpf_perf_"..i, function(val) scale_perf_val(i, tab.key(param_list, "cutoff_hpf"), val) end)
  end
end

return svdrm