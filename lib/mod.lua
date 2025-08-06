-- sidvagn v0.2.0 @sonoCircuit
-- llllllll.co/t/sidvagn
--
--   nisho superlite - as a mod
--
--    > connect sidecar grid
--            to port 2


local md = require 'core/mods'
local mu = require 'musicutil'
local dm = include 'sidvagn/lib/svdrm'
local rf = include 'sidvagn/lib/reflection'
local nb = include 'sidvagn/lib/nb/lib/nb'


-------------------------- variables --------------------------

-- grid
local gs

-- keyboard
local gk = {}
gk.int_y = 3
gk.num_held = 0
gk.dirty = true
for x = 1, 16 do
  gk[x] = {}
  for y = 1, 16 do
    gk[x][y] = {}
    gk[x][y].active = false
    gk[x][y].note = 0
  end
end

-- active voice
local vox = {}
vox.active = 1
vox.select = false

-- drmfm
local drm = {}
drm.mode = false
drm.held = {}

-- notes
local notes = {}
notes.last = 60
notes.held = {}
notes.int_oct = 0
notes.key_oct = 0
notes.root_oct = 3
notes.root_scale = 60
notes.root_base = 24
notes.active_scale = 2
notes.scale = {}
notes.scale_names = {}
notes.scale_intervals = {}

-- velocity
local vel = {}
vel.baseline = 100
vel.voice = 100
vel.hi = 100
vel.lo = 40
vel.res = 0.01
vel.rise = 1
vel.fall = 0.5
vel.value = 0
vel.timer = nil

-- modulation
local mdl = {}
mdl.res = 0.01
mdl.rise = 1
mdl.fall = 0.5
mdl.value = 0
mdl.timer = nil

-- sequencer
local seq = {}
seq.notes = {}
seq.collected = {}
seq.active = false
seq.hold = false
seq.collecting = false
seq.appending = false
seq.step = 0
seq.rate = 1/4

-- key repeat
local rep = {}
rep.rates = {1/4, 1/8, 3/8, 1/16, 1/3, 3/16, 1/6, 1/32, 3/64, 1/12, 5/16, 3/32, 7/16, 1/24, 9/16}
rep.rate = 1/4
rep.hold = false
rep.active = false
rep.mode = false
rep.key = {}
for i = 1, 4 do
  rep.key[i] = 0
end

--trig patterns
local trig = {}
trig.reset_mode = 1
trig.lock = false
trig.step = 0
trig.step_max = 16
trig.pattern = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}
trig.shortpress = true
trig.keytimer = nil
trig.edit_mode = false

-- key viz
local viz = {}
viz.metro = false
viz.bar = false
viz.beat = false
viz.key_fast = 8
viz.key_mid = 4
viz.key_slow = 4

-- key quantization
local quant = {}
quant.event = {}
quant.active = false
quant.rate = 1/4
quant.value = {1/4, 3/16, 1/6, 1/8, 3/32, 1/12, 1/16, 1/32}
quant.bar = 4

-- events
local eNOTE = 1
local eKIT = 2

-- patterns
local ptn = {}
ptn.rec_modes = {"queued", "synced", "free"}
ptn.rec_mode = "free"
ptn.overdub = false
ptn.clear = false
ptn.focus = 1
ptn.rec_on = false
ptn.duplicating = false
ptn.set_focus = false
ptn.edit = false
ptn.held = {}
for i = 1, 8 do
  ptn.held[i] = {}
  ptn.held[i].num = 0
  ptn.held[i].max = 0
  ptn.held[i].first = 0
  ptn.held[i].second = 0
end



-------------------------- functions --------------------------


-------- scales --------
local function build_scale()
  notes.root_base = notes.root_scale % 12 + 12
  notes.root_oct = math.floor((notes.root_scale - notes.root_base) / 12)
  notes.scale = mu.generate_scale_of_length(notes.root_base, notes.active_scale, 60)
  notes_home = tab.key(notes.scale, notes.root_scale)
  notes.last = notes_home
end


-------- patterns and events --------
local function event_exec(e, n)
  if e.t == eNOTE then
    local octave = (notes.root_oct - e.root) * (#notes.scale_intervals[notes.active_scale] - 1)
    local note_num = notes.scale[util.clamp(e.note + octave, 1, #notes.scale)]
    if e.action == "note_off" then
      local player = params:lookup_param("sidv_nb_player_"..e.i):get_player()
      player:note_off(note_num)
      if n ~= nil then
        table.remove(ptn[n].active_notes[e.i], tab.key(ptn[n].active_notes[e.i], note_num))
      end
    elseif e.action == "note_on" then
      local vel = util.linlin(0, 127, 0, 1, e.vel)
      local player = params:lookup_param("sidv_nb_player_"..e.i):get_player()
      player:note_on(note_num, vel)
      if n ~= nil then
        table.insert(ptn[n].active_notes[e.i], note_num)
      end
    end
  elseif e.t == eKIT then
    dm.trig(e.i, e.vel)
    if drm.mode then
      local x = e.i < 5 and e.i + 3 or e.i + 5
      gk[x][3].active = true
      gk.dirty = true
      clock.run(function()
        clock.sleep(1/30)
        gk[x][3].active = false
        gk.dirty = true
      end)
    end
  end
end

local function event_rec(e)
  if not (ptn[ptn.focus].play == 0 and e.action == "note_off") then
    ptn[ptn.focus]:watch(e)
  end
end

local function event(e)
  if (quant.active and not (rep.active or seq.active)) then
    table.insert(quant.event, e)
  else
    event_rec(e)
    event_exec(e)
  end
end

local function event_q_clock()
  while true do
    clock.sync(quant.rate)
    if #quant.event > 0 then
      for _, e in ipairs(quant.event) do
        event_rec(e)
        event_exec(e)
      end
      quant.event = {}
    end
  end
end

local function clear_active_notes(i)
  for voice = 1, 2 do
    if #ptn[i].active_notes[voice] > 0 and ptn[i].endpoint > 0 then
      for _, note in ipairs(ptn[i].active_notes[voice]) do
        local player = params:lookup_param("sidv_nb_player_"..voice):get_player()
        player:note_off(note)
      end
      ptn[i].active_notes[voice] = {}
    end
  end
end

local function track_pattern_pos(i)
  local size = math.floor(ptn[i].endpoint / 16)
  if ptn[i].step % size == 1 then
    local prev_pos = ptn[i].position
    ptn[i].position = math.floor((ptn[i].step) / size) + 1
    if i == ptn.focus then gk.dirty = true end
  end
end

local function step_one_indicator(i)
  ptn[i].pulse_key = true
  gk.dirty = true
  clock.run(function()
    clock.sleep(1/15)
    ptn[i].pulse_key = false
    gk.dirty = true
  end) 
end

local function catch_held_notes(i, action)
  if #notes.held > 0 and not (seq.active or rep.active) then
    if ptn.rec_mode ~= "synced" and action == "note_on" then
      return
    else
      local s = ptn[i].step
      for n, v in ipairs(notes.held) do
        local e = {t = eNOTE, i = vox.active, root = notes.root_oct, note = v, vel = vel.voice, action = action}
        ptn[i]:watch(e, s)
      end
    end
  end
end

for i = 1, 8 do
  ptn[i] = rf.new(i)
  ptn[i].process = event_exec
  ptn[i].start_callback = function() step_one_indicator(i) clear_active_notes(i) end
  ptn[i].start_rec_callback = function() catch_held_notes(i, "note_on") end
  ptn[i].end_of_loop_callback = function() end
  ptn[i].end_of_rec_callback = function() catch_held_notes(i, "note_off") end
  ptn[i].end_callback = function() clear_active_notes(i) gk.dirty = true end
  ptn[i].step_callback = function() track_pattern_pos(i) end
  ptn[i].active_notes = {}
  for voice = 1, 2 do
    ptn[i].active_notes[voice] = {}
  end
end

local function num_rec_enabled()
  local num_enabled = 0
  for i = 1, 8 do
    if ptn[i].rec_enabled > 0 then
      num_enabled = num_enabled + 1
    end
  end
  return num_enabled
end

local function reset_pattern_length(i)
  ptn[i].endpoint = ptn[i].endpoint_init
  ptn[i].step_max = ptn[i].endpoint_init
  if (ptn[i].endpoint_init % 64 ~= 0 or ptn[i].endpoint_init < 128) then
    ptn[i].manual_length = true
  end
end

local function stop_all_patterns()
  for i = 1, 8 do
    if ptn[i].play == 1 then
      ptn[i]:stop()
    end
  end
end

local function paste_seq_pattern(i)
  if #seq.notes > 0 then
    for n = 1, #seq.notes do
      local s = math.floor((n - 1) * (seq.rate * 64) + 1)
      local e = math.floor(s + ((seq.rate / 2) * 64))
      if seq.notes[n] > 0 then
        if not ptn[i].event[s] then
          ptn[i].event[s] = {}
        end
        if not ptn[i].event[e] then
          ptn[i].event[e] = {}
        end
        local on = {root = notes.root_oct, note = seq.notes[n], vel = vel.voice, action = "note_on"}
        local off = {root = notes.root_oct, note = seq.notes[n], vel = vel.voice, action = "note_off"}
        table.insert(ptn[i].event[s], on)
        table.insert(ptn[i].event[e], off)
        ptn[i].count = ptn[i].count + 2
      end
    end
    ptn[i].endpoint = #seq.notes * (seq.rate * 64)
    ptn[i].endpoint_init = ptn[i].endpoint
    ptn[i].step_max = ptn[i].endpoint
    ptn[i].manual_length = true
  end
end


-------- start/stop callback --------
--[[
function clock.transport.start()
  seq.step = 0
  trig.step = 0
end

function clock.transport.stop()
  stop_all_patterns()
  dont_panic()
  seq.active = false
  seq.step = 0
  gk.dirty = true
end
]]

-------- clock coroutines --------
local function set_pattern_loop(i, focus)
  clock.sync(1)
  local segment = math.floor(ptn[focus].endpoint / 16)
  ptn[i].step_min = segment * (math.min(ptn.held[focus].first, ptn.held[focus].second) - 1)
  ptn[i].step_max = segment * math.max(ptn.held[focus].first, ptn.held[focus].second)
  ptn[i].step = ptn[i].step_min
  ptn[i].step_min_viz = math.min(ptn.held[focus].first, ptn.held[focus].second)
  ptn[i].step_max_viz = math.max(ptn.held[focus].first, ptn.held[focus].second)
  ptn[i].looping = true
  clear_active_notes(i)
end

local function clear_pattern_loop(i, beat_sync)
  clock.sync(beat_sync)
  ptn[i].step = 0
  ptn[i].step_min = 0
  ptn[i].step_max = ptn[i].endpoint
end

local function vizclock()
  local counter = 0
  while true do
    clock.sync(1/8)
    counter = util.wrap(counter + 1, 1, 8)
    -- fast
    viz.key_fast = viz.key_fast == 8 and 12 or 8
    if ptn.rec_on then gk.dirty = true end
    -- mid
    if counter % 2 == 0 then
      viz.key_mid = util.wrap(viz.key_mid + 1, 4, 12)
      if ptn.edit then gk.dirty = true end
    end
    -- slow
    if counter % 4 == 0 then
      viz.key_slow = util.wrap(viz.key_slow + 1, 4, 12)
      if (rep.hold or ptn.clear) then gk.dirty = true end
    end
  end
end

local function ledpulse_bar()
  while true do
    clock.sync(quant.bar)
    viz.bar = true
    gk.dirty = true
    clock.run(function()
      clock.sleep(1/30)
      viz.bar = false
      gk.dirty = true
    end)
  end
end

local function ledpulse_beat()
  while true do
    clock.sync(1)
    viz.beat = true
    gk.dirty = true
    clock.run(function()
      clock.sleep(1/30)
      viz.beat = false
      gk.dirty = true
    end)
  end
end

local function set_metronome(mode)
  if mode == "on" then
    barviz = clock.run(ledpulse_bar)
    beatviz = clock.run(ledpulse_beat)
    viz.metro = true
  else
    clock.cancel(barviz)
    clock.cancel(beatviz)
    viz.metro = false
  end
end

local function run_seq()
  while true do
    clock.sync(seq.rate)
    if seq.active then
      if trig.step >= trig.step_max then trig.step = 0 end
      trig.step = trig.step + 1
      if trig.pattern[trig.step] == 1 and #seq.notes > 0 then
        if seq.step >= #seq.notes then seq.step = 0 end
        seq.step = seq.step + 1
        if seq.notes[seq.step] > 0 then
          local current_note = seq.notes[seq.step]
          local e = {t = eNOTE, i = vox.active, root = notes.root_oct, note = current_note, vel = vel.voice, action = "note_on"} event(e)
          clock.run(function()
            clock.sync(seq.rate / 2)
            local e = {t = eNOTE, i = vox.active, root = notes.root_oct, note = current_note, action = "note_off"} event(e)
          end)
        end
      end
      if trig.edit_mode then gk.dirty = true end
    end
  end
end

local function run_keyrepeat()
  while true do
    clock.sync(rep.rate)
    if rep.active then
      if trig.step >= trig.step_max then trig.step = 0 end
      trig.step = trig.step + 1
      if trig.pattern[trig.step] == 1 then
        -- notes
        if #notes.held > 0 then
          for _, v in ipairs(notes.held) do
            local e = {t = eNOTE, i = vox.active, root = notes.root_oct, note = v, vel = vel.voice, action = "note_on"} event(e)
            clock.run(function()
              clock.sync(rep.rate / 2)
              local e = {t = eNOTE, i = vox.active, root = notes.root_oct, note = v, action = "note_off"} event(e)
            end)
          end
        end
        -- kit
        if #drm.held > 0 then
          for _, v in ipairs(drm.held) do
            local e = {t = eKIT, i = v, vel = vel.voice} event(e)
          end
        end
      end
      if trig.edit_mode then gk.dirty = true end
    end
  end
end


-------- velocity modulation --------
local function set_velocity(val)
  vel.voice = util.linlin(0, 1, vel.baseline, 127, val)
  gk.dirty = true
end

local function vl_ramp_up()
  local inc = (1 - vel.value) / (vel.rise / vel.res)
  while vel.value < 1 do
    vel.value = util.clamp(vel.value + inc, 0, 1)
    set_velocity(vel.value)
    clock.sleep(vel.res)
  end
end

local function vl_ramp_down()
  local inc = vel.value / (vel.fall / vel.res)
  while vel.value > 0 do
    vel.value = util.clamp(vel.value - inc, 0, 1)
    set_velocity(vel.value)
    clock.sleep(vel.res)
  end
end


-------- nb modulation --------
local function set_modulation(val)
  local player = params:lookup_param("sidv_nb_player_"..vox.active):get_player()
  player:modulate(val)
  gk.dirty = true
end

local function mdl_ramp_up()
  local inc = (1 - mdl.value) / (mdl.rise / mdl.res)
  while mdl.value < 1 do
    mdl.value = util.clamp(mdl.value + inc, 0, 1)
    set_modulation(mdl.value)
    clock.sleep(mdl.res)
  end
end

local function mdl_ramp_down()
  local inc = mdl.value / (mdl.fall / mdl.res)
  while mdl.value > 0 do
    mdl.value = util.clamp(mdl.value - inc, 0, 1)
    set_modulation(mdl.value)
    clock.sleep(mdl.res)
  end
end


-------- key repeate and trig reset --------
local function set_trig_start()
  trig.lock = false
  trig.step = 0
  if trig.reset_mode > 2 then
    if not trig.lock then
      local beat_sync = trig.reset_mode == 3 and 1 or quant.bar
      clock.run(function()
        clock.sync(beat_sync, -1/8)
        trig.step = 0
        trig.lock = true
      end)
    end
  end
end

local function reset_trig_step()
  if trig.reset_mode == 1 then
    trig.step = 0
  elseif trig.reset_mode == 2 then
    if not trig.lock then
      trig.step = 0
      trig.lock = true
    end
  end
end

local function set_repeat_rate(k1, k2, k3, k4, keypress)
  if not rep.active then
    set_trig_start()
  end
  rep.active = (k1 + k2 + k3 + k4) > 0 and true or false
  local idx = tonumber(tostring(k4..k3..k2..k1), 2)
  if idx > 0 then
    rep.rate = rep.rates[idx] * 4
  end
  if not rep.active then trig.lock = false end
end


-------- utilities --------
local function dont_panic()
  if #notes.held > 0 then
    for _, note in ipairs(notes.held) do
      local player = params:lookup_param("sidv_nb_player_"..vox.active):get_player()
      player:note_off(note)
    end
  end
  for i = 1, 8 do
    clear_active_notes(i)
  end
  nb:stop_all() -- should suffice, but who knows...
  notes.held = {}
end

local function round_form(param, quant, form)
  return(util.round(param, quant)..form)
end


-------------------------- grid interface --------------------------

-------- gridkey functions --------
local function pattern_keys(i)
  if ptn.focus ~= i and num_rec_enabled() == 0 then
    ptn.focus = i
  end
  if not (ptn.duplicating) then
    if ptn.clear then
      if ptn[i].count > 0 then
        clear_active_notes(i)
        ptn[i]:clear()
      end
    else
      if ptn[i].play == 0 then
        local beat_sync = ptn[i].launch == 2 and 1 or (ptn[i].launch == 3 and quant.bar or nil)
        if ptn[i].count == 0 then
          if seq.appending then
            paste_seq_pattern(i)
          else
            if num_rec_enabled() == 0 then
              local mode = ptn.rec_mode == "synced" and 1 or 2
              local dur = ptn.rec_mode ~= "free" and ptn[i].length or nil
              ptn[i]:set_rec(mode, dur, beat_sync)
              ptn.rec_on = true
            else
              ptn[i]:set_rec(0)
              ptn[i]:stop()
              ptn.rec_on = false
            end
          end
        else
          ptn[i]:start(beat_sync)
        end
      else
        if ptn.overdub then
          if ptn[i].rec == 1 then
            ptn[i]:set_rec(0)
            ptn[i]:undo()
            ptn.rec_on = false
          else
            ptn[i]:set_rec(1)  
            ptn.rec_on = true          
          end
        else
          if ptn[i].rec == 1 then
            ptn[i]:set_rec(0)
            ptn.rec_on = false
            if ptn[i].count == 0 then
              ptn[i]:stop()
            end
          else
            ptn[i]:stop()
          end
        end
      end
    end
  else
    ptn[i]:double()
  end
end

local function pattern_playhead(x, z)
  if z == 1 and ptn.held[ptn.focus].num then ptn.held[ptn.focus].max = 0 end
  ptn.held[ptn.focus].num = ptn.held[ptn.focus].num + (z * 2 - 1)
  if ptn.held[ptn.focus].num > ptn.held[ptn.focus].max then ptn.held[ptn.focus].max = ptn.held[ptn.focus].num end
  if z == 1 then
    if ptn.held[ptn.focus].num == 1 then
      ptn.held[ptn.focus].first = x
    elseif ptn.held[ptn.focus].num == 2 then
      ptn.held[ptn.focus].second = x
    end
    if ptn.clear then
      for i = 1, 8 do
        if ptn[i].looping then
          clock.run(clear_pattern_loop, i, quant.bar)
          ptn[i].looping = false
        end
      end
    end
  else
    if ptn.held[ptn.focus].num == 1 and ptn.held[ptn.focus].max == 2 then
      if ptn.overdub then
        for i = 1, 8 do
          if ptn[i].play == 1 then
            clock.run(set_pattern_loop, i, ptn.focus)
          end
        end
      else
        clock.run(set_pattern_loop, ptn.focus, ptn.focus)
      end
    elseif ptn[ptn.focus].looping and ptn.held[ptn.focus].max < 2 then
      local dur = ptn[ptn.focus].launch == 2 and 1 or (ptn[ptn.focus].launch == 3 and quant.bar or ptn[ptn.focus].quantize)
      clock.run(clear_pattern_loop, ptn.focus, dur)
      ptn[ptn.focus].looping = false
    elseif not (ptn[ptn.focus].looping or pattern_reset) and ptn.held[ptn.focus].max < 2 then
      clock.run(function()
        clock.sync(quant.rate)
        local segment = math.floor(ptn[ptn.focus].endpoint / 16)
        ptn[ptn.focus].step = segment * (x - 1)
      end)
    end
  end    
end

local function trig_pattern(x, z)
  local i = x
  if ptn.clear then
    if z == 1 then
      trig.pattern = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}
    end
  else
    if z == 1 then
      trig.shortpress = true
      if trig.keytimer ~= nil then
        clock.cancel(trig.keytimer)
      end
      trig.keytimer = clock.run(function()
        clock.sleep(1/6)
        trig.shortpress = false
        trig.step_max = x
      end)
    else
      if trig.keytimer ~= nil then
        clock.cancel(trig.keytimer)
      end
      if trig.shortpress then
        trig.pattern[x] = 1 - trig.pattern[x]
      end
    end
  end
end

local function add_note(x, y, note)
  -- keep track of held notes
  gk[x][y].note = note
  table.insert(notes.held, note)
  -- collect notes
  if seq.collecting then
    table.insert(seq.collected, note)
  end
  -- insert notes
  if seq.active and not seq.collecting then
    if gk.num_held == 1 then
      reset_trig_step()
      if seq.hold then seq.notes = {} end
    end
    table.insert(seq.notes, note)
  end
  -- play notes
  if not seq.active then
    if rep.active then
      if gk.num_held == 1 then
        reset_trig_step()
      end
    else
      local e = {t = eNOTE, i = vox.active, root = notes.root_oct, note = note, vel = vel.voice, action = "note_on"} event(e)
    end
  end
end

local function remove_note(x, y)
  if seq.active and not (seq.collecting or seq.hold) then
    table.remove(seq.notes, tab.key(notes.held, gk[x][y].note))
  end
  if not (seq.active or rep.active) then
    local e = {t = eNOTE, i = vox.active, root = notes.root_oct, note = gk[x][y].note, action = "note_off"} event(e)
  end
  table.remove(notes.held, tab.key(notes.held, gk[x][y].note))
end

local function int_grid(x, y, z)
  gk.num_held = gk.num_held + (z * 2 - 1)
  gk[x][y].active = z == 1 and true or false
  if z == 1 then
    if x > 3 and x < 8 then
      local note = util.clamp(notes.last + (x - 8), 1, #notes.scale)
      notes.last = note
      add_note(x, y, note)
    elseif x > 7 and x < 10 then
      add_note(x, y, notes.last)
    elseif x > 9 and x < 14 then
      local note = util.clamp(notes.last + (x - 9), 1, #notes.scale)
      notes.last = note
      add_note(x, y, note)
    end
  else
    remove_note(x, y)
  end
end

local function kit_grid(x, z)
  if (x > 3 and x < 8) or (x > 9 and x < 14) then
    local kit_voice = x < 8 and x - 3 or x - 5
    if z == 1 then
      if not rep.active then
        local e = {t = eKIT, i = kit_voice, vel = vel.voice} event(e)
      end
      table.insert(drm.held, kit_voice)
    else
      table.remove(drm.held, tab.key(drm.held, kit_voice))
    end
  elseif x == 8 or x == 9 then
    local action = z == 1 and "on" or "off"
    local slot = x - 7
    dm.drmf_perf(action, slot, quant.bar)
  end
end

local function scale_grid(x, y, z)
  gk.num_held = gk.num_held + (z * 2 - 1)
  gk[x][y].active = z == 1 and true or false
  if z == 1 then
    local octave = #notes.scale_intervals[notes.active_scale] - 1
    local note = (x - 2) + ((8 - y) * gk.int_y) + (notes.key_oct + 3) * octave
    add_note(x, y, note)
    notes.last = note + octave * notes.int_oct
  elseif z == 0 then
    remove_note(x, y)
  end
end

local function key_events(y, z)
  if rep.mode then
    local slot = y - 4
    if rep.hold then
      if z == 1 then
        rep.key[slot] = 1 - rep.key[slot]
      end
    else
      rep.key[slot] = z
    end
    set_repeat_rate(rep.key[1], rep.key[2], rep.key[3], rep.key[4], z)
  else
    if y == 5 and z == 1 then
      seq.active = not seq.active
      seq.step = 0
      if seq.active then
        set_trig_start()
      else
        seq.notes = {}
      end
    elseif y == 6 then
      seq.collecting = z == 1 and true or false
      if z == 0 and #seq.collected > 0 then
        seq.step = 0
        reset_trig_step()
        seq.notes = {table.unpack(seq.collected)}
      else
        seq.collected = {}
      end
      dirtyscreen = true
    elseif y == 7 then
      seq.appending = z == 1 and true or false
    elseif y == 8 and z == 1 then
      seq.hold = not seq.hold
      if not seq.hold then
        seq.notes = {table.unpack(notes.held)}
      end
    end
  end
end


-------- gridkey  --------
local function sidv_grid(x, y, z)
  if y == 1 then
    if x == 1 then
      ptn.clear = z == 1 and true or false
    elseif x == 2 then
      if ptn.clear then
        if z == 1 then dont_panic() end
      else
        ptn.duplicating = z == 1 and true or false
      end
    elseif x == 3 then
      if ptn.clear then
        if z == 1 then stop_all_patterns() end
      else
        ptn.overdub = z == 1 and true or false
      end
    elseif x == 4 then
      if ptn.clear and ptn.edit then
        if z == 1 then reset_pattern_length(ptn.focus) end
      else
        ptn.set_focus = z == 1 and true or false
      end
    elseif x > 4 and x < 13 and y == 1 and z == 1 then
      if ptn.set_focus then
        ptn.focus = x - 4
      else
        pattern_keys(x - 4)
      end
    elseif x == 13 and z == 1 then
      ptn.edit = not ptn.edit
    elseif x > 13 and z == 1 then
      if ptn.edit then
        ptn[ptn.focus].launch = 17 - x
      else
        ptn.rec_mode = ptn.rec_modes[x - 13]
      end
    end
  elseif y == 2 then
    if ptn.edit then
      if z == 1 then
        ptn[ptn.focus].beatnum = x
        ptn[ptn.focus].manual_length = false
        ptn[ptn.focus].length = ptn[ptn.focus].beatmult * ptn[ptn.focus].beatnum
        ptn[ptn.focus]:set_length(ptn[ptn.focus].length)
      end
    else
      pattern_playhead(x, z)
    end
  elseif y == 3 then
    if x == 1 and z == 1 then
      set_metronome(viz.metro and "off" or "on")
    elseif x == 2 and z == 1 then
      quant.active = not quant.active
    elseif x == 3 then
      vox.select = z == 1 and true or false
      if z == 1 then
        vox.active = vox.active == 1 and 2 or 1
      end
    elseif x > 3 and x < 14 then
      if drm.mode then
        kit_grid(x, z)
      else
        int_grid(x, y, z)
      end
    elseif x == 14 and z == 1 then
      drm.mode = not drm.mode
    elseif x == 15 and z == 1 then
      trig.edit_mode = not trig.edit_mode
    elseif x == 16 and z == 1 then
      rep.mode = not rep.mode
      if rep.mode then
        if seq.active then
          seq.active = false
        end
      else
        rep.hold = false
        for i = 1, 4 do
          rep.key[i] = 0
        end
        set_repeat_rate(0, 0, 0, 0, z)
      end
    end
  elseif y == 4 then
    if ptn.edit then
      if z == 1 then
        ptn[ptn.focus].beatmult = x
        ptn[ptn.focus].manual_length = false
        ptn[ptn.focus].length = ptn[ptn.focus].beatmult * ptn[ptn.focus].beatnum
        ptn[ptn.focus]:set_length(ptn[ptn.focus].length)
      end
    else
      if trig.edit_mode then
        trig_pattern(x, z)
      elseif seq.active then
        if x > 4 and x < 13 and z == 1 then
          params:set("sidv_key_seq_rate", x - 4)
        end
      end
    end
  elseif y > 4 then
    if x == 1 then
      if (y == 5 or y == 6) and z == 1 then
        local inc = y == 5 and 1 or -1
        notes.int_oct = util.clamp(notes.int_oct + inc, -3, 3)
      elseif (y == 7 or y == 8) and z == 1 then
        local inc = y == 7 and 1 or -1
        notes.key_oct = util.clamp(notes.key_oct + inc, -3, 3)
      end
    elseif x == 2 then
      if y == 5 then 
        if mdl.timer ~= nil then
          clock.cancel(mdl.timer)
        end
        mdl.timer = clock.run(z == 1 and mdl_ramp_up or mdl_ramp_down)
      elseif y == 6 then 
        vel.baseline = vel.hi
        vel.voice = vel.hi
      elseif y == 7 then
        vel.baseline = vel.lo
        vel.voice = vel.lo
      elseif y == 8 then
        if vel.timer ~= nil then
          clock.cancel(vel.timer)
        end
        vel.timer = clock.run(z == 1 and vl_ramp_up or vl_ramp_down)
      end
    elseif x > 2 and x < 15 then
      scale_grid(x, y, z)
    elseif x == 15 then
      if (y == 6 or y == 7) and z == 1 then
        if seq.collecting then
          table.insert(seq.collected, 0)
        end
      elseif y == 8 and z == 1 then
        if rep.mode then
          rep.hold = not rep.hold
          if not rep.hold then
            for i = 1, 4 do
              rep.key[i] = 0
            end
            set_repeat_rate(0, 0, 0, 0, z)
          end
        end
      end
    elseif x == 16 then
      key_events(y, z)
    end
  end
  gk.dirty = true
end 


-------- gridredraw  --------
local function sidv_gridredraw()
  gs:all(0)
  -- pattern options
  gs:led(1, 1, ptn.clear and viz.key_slow or 8)
  gs:led(2, 1, ptn.clear and viz.key_slow or (ptn.duplicating and 15 or 6))
  gs:led(3, 1, ptn.clear and viz.key_slow or (ptn.overdub and 15 or 4))
  gs:led(4, 1, ptn.set_focus and 15 or 0)
  gs:led(13, 1, ptn.edit and viz.key_mid or 0)
  if ptn.edit then
    for i = 1, 3 do
      gs:led(17 - i, 1, ptn[ptn.focus].launch == i and 12 or 2)
    end
  else
    for i = 1, 3 do
      gs:led(13 + i, 1, ptn.rec_mode == ptn.rec_modes[i] and 12 or 4)
    end
  end
  -- pattern_keys
  for i = 1, 8 do
    if ptn.set_focus then
      gs:led(i + 4, 1, ptn.focus == i and 6 or 1)
    else
      if ptn[i].rec == 1 and ptn[i].play == 1 then
        gs:led(i + 4, 1, viz.key_fast)
      elseif ptn[i].rec_enabled == 1 then
        gs:led(i + 4, 1, 15)
      elseif ptn[i].play == 1 then
        gs:led(i + 4, 1, ptn[i].pulse_key and 15 or 12)
      elseif ptn[i].count > 0 then
        gs:led(i + 4, 1, 6)
      else
        gs:led(i + 4, 1, 2)
      end
    end
  end
  --pattern trigs
  if ptn.edit then
    for x = 1, 16 do
      gs:led(x, 2, ptn[ptn.focus].beatnum >= x and 2 or 0)
    end
  else
    if ptn[ptn.focus].looping then
      local min = ptn[ptn.focus].step_min_viz
      local max = ptn[ptn.focus].step_max_viz
      for i = min, max do
        gs:led(i, 2, 4)
      end
    end
    if ptn[ptn.focus].play == 1 and ptn[ptn.focus].endpoint > 0 then
      gs:led(ptn[ptn.focus].position, 2, 10)
    end
  end
  -- metro and key q
  if viz.metro then
    gs:led(1, 3, viz.bar and 15 or (viz.beat and 8 or 3)) -- Q flash
  else
    gs:led(1, 3, 3)
  end
  gs:led(2, 3, quant.active and 8 or 4)
  -- int/kit grid
  if drm.mode then
    local slot = params:get("drmfm_perf_slot")
    local perf = math.floor(params:get("drmfm_perf_amt") * 15)
    gs:led(8, 3, vox.select and (vox.active == 1 and 15 or 0) or (slot == 1 and perf or 0))
    gs:led(9, 3, vox.select and (vox.active == 2 and 15 or 0) or (slot == 2 and perf or 0))
    for i = 1, 4 do
      gs:led(i + 3, 3, gk[i + 3][3].active and 15 or 4)
      gs:led(i + 9, 3, gk[i + 9][3].active and 15 or 4)
    end
  else
    local cntpress = (gk[8][3].active or gk[9][3].active) and 15 or 1
    gs:led(8, 3, vox.select and (vox.active == 1 and 15 or 0) or cntpress)
    gs:led(9, 3, vox.select and (vox.active == 2 and 15 or 0) or cntpress)
    for i = 1, 4 do
      gs:led(i + 3, 3, gk[i + 3][3].active and 15 or (12 - i * 2)) -- intervals dec
      gs:led(i + 9, 3, gk[i + 9][3].active and 15 or (2 + i * 2)) -- intervals inc
    end
  end
  -- trig edit and seq/keyrep
  gs:led(15, 3, trig.edit_mode and 8 or 4)
  gs:led(16, 3, rep.mode and 10 or 6)
  -- event trigs
  if ptn.edit then
    for x = 1, 16 do
      gs:led(x, 4, ptn[ptn.focus].beatmult >= x and 2 or 0)
    end
  else
    if trig.edit_mode then
      for x = 1, 16 do
        if x <= trig.step_max then
          gs:led(x, 4, (trig.step == x and (seq.active or rep.active)) and 14 or (trig.pattern[x] == 1 and 6 or 1))
        end
      end
    elseif seq.active then
      for x = 1, 8 do
        gs:led(x + 4, 4, params:get("sidv_key_seq_rate") == x and 6 or 1)
      end
    end
  end
  -- octave options
  gs:led(1, 5, 8 + notes.int_oct * 2)
  gs:led(1, 6, 8 - notes.int_oct * 2)
  gs:led(1, 7, 8 + notes.key_oct * 2)
  gs:led(1, 8, 8 - notes.key_oct * 2)
  -- afterfouch, modwheel, pitchbend
  gs:led(2, 5, math.floor(mdl.value * 15))
  gs:led(2, 6, vel.baseline == vel.hi and 2 or 0)
  gs:led(2, 7, vel.baseline == vel.lo and 2 or 0)
  gs:led(2, 8, math.floor(vel.value * 15))
  -- key events
  if rep.mode then
    for i = 1, 4 do
      gs:led(16, i + 4, rep.key[i] == 1 and 15 or i * 2)
    end
    gs:led(15, 8, rep.hold and viz.key_slow or 0)
  else
    gs:led(16, 5, seq.active and 10 or 4)
    gs:led(16, 6, seq.collecting and 10 or 2)
    gs:led(16, 7, seq.appending and 10 or 2)
    gs:led(16, 8, seq.hold and 15 or 2)
  end
  -- keyboard
  local octave = #notes.scale_intervals[notes.active_scale] - 1
  for i = 1, 12 do
    gs:led(i + 2, 5, gk[i + 2][5].active and 15 or (((i + gk.int_y * 3) % octave) == 1 and 10 or 2))
    gs:led(i + 2, 6, gk[i + 2][6].active and 15 or (((i + gk.int_y * 2) % octave) == 1 and 10 or 2))
    gs:led(i + 2, 7, gk[i + 2][7].active and 15 or (((i + gk.int_y) % octave) == 1 and 10 or 2))
    gs:led(i + 2, 8, gk[i + 2][8].active and 15 or ((i % octave) == 1 and 10 or 2))
  end
  gs:refresh()
end

local function hardware_redraw()
  if gk.dirty then
    sidv_gridredraw()
    gk.dirty = false
  end
end


--------------------- init -----------------------

local function init_params()
  
  notes.scale_names = {}
  for i = 1, #mu.SCALES do
    table.insert(notes.scale_names, string.lower(mu.SCALES[i].name))
  end

  notes.scale_intervals = {}
  for i = 1, #mu.SCALES do
    notes.scale_intervals[i] = {table.unpack(mu.SCALES[i].intervals)}
  end
  
  params:add_separator("sidvagn_params", "sidvagn")

  nb:init()
  nb:add_param("sidv_nb_player_1", "player [one]")
  nb:add_param("sidv_nb_player_2", "player [two]")

  params:add_group("sidv_keys_params", "options", 17)

  params:add_separator("sidv_scale_params", "scale")
  params:add_option("sidv_scale", "scale", notes.scale_names, 2)
  params:set_action("sidv_scale", function(val) notes.active_scale = val build_scale() gk.dirty = true end)

  params:add_number("sidv_root_note", "root note", 24, 84, 60, function(param) return mu.note_num_to_name(param:get(), true) end)
  params:set_action("sidv_root_note", function(val) notes.root_scale = val build_scale() gk.dirty = true end)

  params:add_number("sidv_scale_keys_y", "key interval [y]", 2, 8, 4)
  params:set_action("sidv_scale_keys_y", function(val) gk.int_y = val - 1 gk.dirty = true end)

  params:add_separator("sidv_timing_params", "timing")
  params:add_number("sidv_time_signature", "time signature", 2, 9, 4, function(param) return param:get().."/4" end)
  params:set_action("sidv_time_signature", function(val) quant.bar = val end)
        
  params:add_option("sidv_key_quant_value", "key quantization", {"1/4", "3/16", "1/6", "1/8", "3/32", "1/12", "1/16","1/32"}, 7)
  params:set_action("sidv_key_quant_value", function(idx) quant.rate = quant.value[idx] * 4 end)
  
  params:add_option("sidv_key_seq_rate", "sequencer rate", {"1/4", "3/16", "1/6", "1/8", "3/32", "1/12", "1/16","1/32"}, 7)
  params:set_action("sidv_key_seq_rate", function(idx) seq.rate = quant.value[idx] * 4 end)

  params:add_option("sidv_trig_reset_mode", "trig reset mode", {"manual", "lock", "beat", "bar"}, 1)
  params:set_action("sidv_trig_reset_mode", function(mode) trig.reset_mode = mode end)

  params:add_separator("sidv_velocity_params", "velocity")
  params:add_number("sidv_note_velocity_high", "high", 65, 127, 100)
  params:set_action("sidv_note_velocity_high", function(val) vel.hi = val end)

  params:add_number("sidv_note_velocity_low", "low", 1, 64, 40)
  params:set_action("sidv_note_velocity_low", function(val) vel.lo = val end)

  params:add_control("sidv_velocity_rise", "rise time", controlspec.new(0.1, 10, "lin", 0.1, 1), function(param) return round_form(param:get(), 0.1, "s") end)
  params:set_action("sidv_velocity_rise", function(val) vel.rise = val end)

  params:add_control("sidv_velocity_fall", "fall time", controlspec.new(0.1, 10, "lin", 0.1, 0.5), function(param) return round_form(param:get(), 0.1, "s") end)
  params:set_action("sidv_velocity_fall", function(val) vel.fall = val end)

  params:add_separator("sidv_modulation_params", "modulation")
  params:add_control("sidv_modultaion_rise", "rise time", controlspec.new(0.1, 10, "lin", 0.1, 1), function(param) return round_form(param:get(), 0.1, "s") end)
  params:set_action("sidv_modultaion_rise", function(val) mdl.rise = val end)

  params:add_control("sidv_modulation_fall", "fall time", controlspec.new(0.1, 10, "lin", 0.1, 0.5), function(param) return round_form(param:get(), 0.1, "s") end)
  params:set_action("sidv_modulation_fall", function(val) mdl.fall = val end)

  dm.add_params()

  nb:add_player_params()

  build_scale()

  params:bang()

end

local function init_clocks()
  -- metro
  sidv_redrawtimer = metro.init(hardware_redraw, 1/30, -1)
  sidv_redrawtimer:start()
  -- clocks
  clock.run(event_q_clock)
  clock.run(run_seq)
  clock.run(run_keyrepeat)
  clock.run(vizclock)
  set_metronome("on")
end

local function init_grid()
  gs = grid.connect(2)
  gs.key = sidv_grid
end

local function sidv_init()
  init_grid()
  init_params()
  init_clocks()
end

local function sidv_cleanup()
  dont_panic()
  if ptn ~= nil then
    for i = 1, 8 do
      ptn[i]:clear()
    end
  end
  if trig ~= nil then
    trig.pattern = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}
  end
end


-------------------------- mod hooks --------------------------

md.hook.register("script_post_init", "sidvagn_post_init", sidv_init)
md.hook.register("script_post_cleanup", "sidvagn_post_cleanup", sidv_cleanup)
