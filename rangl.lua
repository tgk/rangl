-- rangl: recording arc grains
-- 1.0.0 @tgk
--
-- load files via param menu
--
-- K3 to switch modes:
-- -- SPEED
--  K2 then touch arc to
--    set speed to zero
-- -- PITCH
--  K2 sets fine control
-- -- RECORD
--  touch arc to select
--  track
--  K2 + K3 start recording
--    then K2 + K3 or touch
--    arc to stop
--  K2 + K3 stop recording
--    if recording
-- -- LEVEL
--  adjust levels with arc
-- -- FRICTION
--  adjust friction with arc


engine.name = 'Glut'

tau = math.pi * 2
VOICES = 4
positions = {-1,-1,-1,-1}
modes = {"speed", "pitch", "record", "level", "friction"}
mode = 1
armed_voice = 1
recording = false
hold = false

REFRESH_RATE = 0.03
FRICTION_RATE = 1


key = function(n,z)
  if n==2 then hold = z==1 and true or false
  elseif n==3 and hold and mode==3 and z==1 then
    recording = not recording
    if recording then
      start_recording()
    else
      stop_recording()
    end
  elseif n==3 and z==1 then
    mode = mode + 1
    if mode > #modes then mode = 1 end
  end
  redraw()
end

a = arc.connect()

a.delta = function(n,d)
  if mode==1 then
    if hold == true then
      params:set(n.."speed",0)
    else
      params:delta(n.."speed",d/10)
    end
  elseif mode==2 then
    if hold == true then
      params:delta(n.."pitch",d/20)
    else
      params:delta(n.."pitch",d/2)
    end
  elseif mode==3 then
    if armed_voice ~= n and recording then
      recording = false
      stop_recording()
    end
    armed_voice = n
  elseif mode==4 then
    params:delta(n.."volume", d)
  elseif mode==5 then
    params:delta(n.."friction", d)
  end
end

arc_redraw = function()
  a:all(0)
  if mode == 1 then
    for v=1,VOICES do
      a:segment(v,positions[v]*tau,tau*positions[v]+0.2,15)
    end
  elseif mode == 2 then
    for v=1,VOICES do
      local pitch = params:get(v.."pitch") / 10
      if pitch > 0 then
        a:segment(v,0.5,0.5+pitch,15)
      else
        a:segment(v,pitch-0.5,-0.5,15)
      end

    end
  elseif mode == 3 then
    if armed_voice > 0 then
      if recording then
        a:segment(armed_voice,positions[armed_voice]*tau+0.3,tau*positions[armed_voice],15)
      else
        a:segment(armed_voice,positions[armed_voice]*tau+0.3,tau*positions[armed_voice],5)
      end
    end
  elseif mode == 4 then
    for v=1,VOICES do
      local percentage = (params:get(v.."volume") + 60) / 80
      a:segment(v,0,percentage*(tau-0.0001),15)
    end
  elseif mode == 5 then
    for v=1,VOICES do
      a:segment(v,0,params:get(v.."friction")*(tau-0.0001)/100,15)
    end
  end
  a:refresh()
end

re = metro.init()
re.time = REFRESH_RATE
re.event = function()
  arc_redraw()
end
re:start()

fr = metro.init()
fr.time = FRICTION_RATE
fr.event = function()
  for v=1,VOICES do
    local friction = params:get(v.."friction")
    if friction > 0 then
      params:set(v.."speed", ((100 - friction)/100)*params:get(v.."speed"))
    end
  end
end
fr:start()


function start_recording()
  tape_start=os.time()
  audio.level_eng_cut(0)
  audio.level_tape_cut(0)
  softcut.buffer_clear()
  for i=1,2 do
    softcut.enable(i,1)
    if i%2==1 then
      softcut.pan(i,1)
      softcut.buffer(i,1)
      softcut.level_input_cut(1,i,1)
      softcut.level_input_cut(2,i,0)
    else
      softcut.pan(i,-1)
      softcut.buffer(i,2)
      softcut.level_input_cut(1,i,0)
      softcut.level_input_cut(2,i,1)
    end
    softcut.level_slew_time(i,0.05)
    softcut.rate_slew_time(i,0.05)
    softcut.level(i,0)
    softcut.rec(i,1)
    softcut.play(i,1)
    softcut.rate(i,1)
    softcut.position(i,0)
    softcut.loop_start(i,0)
    softcut.loop_end(i,121)
    softcut.rec_level(i,1.0)
    softcut.pre_level(i,1.0)
    softcut.post_filter_dry(i,0.0)
    softcut.post_filter_lp(i,1.0)
    softcut.post_filter_rq(i,1.0)
    softcut.post_filter_fc(i,18000)

    softcut.pre_filter_dry(i,1.0)
    softcut.pre_filter_lp(i,1.0)
    softcut.pre_filter_rq(i,1.0)
    softcut.pre_filter_fc(i,18000)
  end
end


function stop_recording()
  for i=1,2 do
    softcut.rec(i,0)
    softcut.play(i,0)
  end
  local tape_name=tape_get_name()
  if tape_name~=nil then
    softcut.buffer_write_stereo(tape_name,0.25,os.time()-tape_start)
  end
  -- load the tape into the current voice
  print("saved to '"..tape_name.."'")
  voice = armed_voice
  clock.run(function()
    clock.sleep(1)
    print("loading!")
    params:set(voice.."sample",tape_name)
  end)
  armed_voice = armed_voice + 1
  if armed_voice > 4 then
    armed_voice = 1
  end
end

function tape_get_name()
  if not util.file_exists(_path.audio.."ash/") then
    os.execute("mkdir -p ".._path.audio.."ash/")
  end
  for index=1,1000 do
    index=string.format("%04d",index)
    local filename=_path.audio.."ash/"..index..".wav"
    if not util.file_exists(filename) then
      do return _path.audio.."ash/"..index..".wav" end
    end
  end
  return nil
end


function init()
  -- polls
  for v = 1, VOICES do
    local phase_poll = poll.set('phase_' .. v, function(pos) positions[v] = pos end)
    phase_poll.time = REFRESH_RATE
    phase_poll:start()
  end

  local sep = ": "

  params:add_taper("reverb_mix", "*"..sep.."mix", 0, 100, 50, 0, "%")
  params:set_action("reverb_mix", function(value) engine.reverb_mix(value / 100) end)

  params:add_taper("reverb_room", "*"..sep.."room", 0, 100, 50, 0, "%")
  params:set_action("reverb_room", function(value) engine.reverb_room(value / 100) end)

  params:add_taper("reverb_damp", "*"..sep.."damp", 0, 100, 50, 0, "%")
  params:set_action("reverb_damp", function(value) engine.reverb_damp(value / 100) end)

  for v = 1, VOICES do
    params:add_separator()

    params:add_file(v.."sample", v..sep.."sample")
    params:set_action(v.."sample", function(file) engine.read(v, file) end)

    params:add_option(v.."play", v..sep.."play", {"off","on"}, 2)
    params:set_action(v.."play", function(x) engine.gate(v, x-1) end)

    params:add_taper(v.."volume", v..sep.."volume", -60, 20, 0, 0, "dB")
    params:set_action(v.."volume", function(value) engine.volume(v, math.pow(10, value / 20)) end)

    params:add_taper(v.."speed", v..sep.."speed", -200, 200, 100, 0, "%")
    params:set_action(v.."speed", function(value) engine.speed(v, value / 100) end)

    params:add_taper(v.."jitter", v..sep.."jitter", 0, 500, 0, 5, "ms")
    params:set_action(v.."jitter", function(value) engine.jitter(v, value / 1000) end)

    params:add_taper(v.."size", v..sep.."size", 1, 500, 100, 5, "ms")
    params:set_action(v.."size", function(value) engine.size(v, value / 1000) end)

    params:add_taper(v.."density", v..sep.."density", 0, 512, 20, 6, "hz")
    params:set_action(v.."density", function(value) engine.density(v, value) end)

    params:add_taper(v.."pitch", v..sep.."pitch", -24, 24, 0, 0, "st")
    params:set_action(v.."pitch", function(value) engine.pitch(v, math.pow(0.5, -value / 12)) end)

    params:add_taper(v.."spread", v..sep.."spread", 0, 100, 0, 0, "%")
    params:set_action(v.."spread", function(value) engine.spread(v, value / 100) end)

    params:add_taper(v.."fade", v..sep.."att / dec", 1, 9000, 1000, 3, "ms")
    params:set_action(v.."fade", function(value) engine.envscale(v, value / 1000) end)

    params:add_taper(v.."friction", v..sep.."friction", 0, 100, 0, 0, "%")
  end
  params:read()
  params:bang()
end


function redraw()
  screen.clear()
  screen.move(64,40)
  screen.level(hold==true and 4 or 15)
  screen.font_face(10)
  screen.font_size(20)
  screen.text_center(modes[mode])
  screen.update()
end
