// drmfm percussion @sonocircuit
// based on the amazing Oilcan @zbs and @sixolet

Svdrm {
	classvar <voxs;
	*initClass {

		StartUp.add {
			voxs = 8.collect {nil};

		  SynthDef(\svDrm,{

				arg out, sendABus, sendBBus,

				freq = 43,
				tune = 0,
				decay = 1,

				sweep_time = 0.1,
				sweep_depth = 0,

				mod_ratio = 1,
				mod_time = 0.1,
				mod_amp = 0,
				mod_fb = 0,
				mod_dest = 0,

				noise_amp = 1,
				noise_decay = 0.3,

				cutoff_lpf = 18000,
				cutoff_hpf = 20,

				phase = 0,
				fold = 0,

				sendA = 0,
				sendB = 0,
				pan = 0,
				level = 1;

				var car_env, mod_env, noise_env, sweep_env, hz, mod, car, noise, sig;

				// rescaling
				freq = freq.midicps * 2.pow(tune / 12);
				fold = fold.linlin(0, 1, 0, 20);
				phase = phase.linlin(0, 1, 0, pi/2);
				mod_fb = mod_fb.linlin(0, 1, 0, 10);

				// envelopes
				car_env = EnvGen.ar(Env.perc(0, decay, curve: -6.0), doneAction: Select.kr(decay >= noise_decay, [0, 2]));
				mod_env = EnvGen.ar(Env.perc(0, decay * mod_time, mod_amp));
				noise_env = EnvGen.ar(Env.perc(0, noise_decay, noise_amp, -6.0), doneAction: Select.kr(decay <= noise_decay, [0, 2]));
				sweep_env = EnvGen.ar(Env.perc(0, decay * sweep_time, sweep_depth));

				// base frequency
				hz = Clip.ar(freq + (sweep_env * 800), 0, 10000);

				// modulator
				mod = SinOscFB.ar(hz * mod_ratio, mod_fb);
				mod = Fold.ar(mod * (fold + 1), -1, 1) * mod_env;

				// carrier
				car = SinOsc.ar(hz + (mod * 10000 * mod_dest), phase);
				car = Fold.ar(car * (fold + 1), -1, 1) * car_env;

				// noise gen
				noise = WhiteNoise.ar(noise_env);

				// mixdown
				sig = car + (mod * (1 - mod_dest)) + noise;

				// filters
				sig = LPF.ar(sig, cutoff_lpf);
				sig = HPF.ar(sig, cutoff_hpf);

				// output stage
				sig = (sig * level).tanh;
				Out.ar(out, Pan2.ar(sig, pan));
				Out.ar(sendABus, sendA * sig);
				Out.ar(sendBBus, sendB * sig);
			}).add;

			OSCFunc.new({ |msg, time, addr, recvPort|
				var syn;
				var idx = msg[1];
				var args = [[
				\freq, \tune, \decay, \sweep_time, \sweep_depth, \mod_ratio, \mod_time, \mod_amp, \mod_fb, \mod_dest,
				\noise_amp, \noise_decay, \cutoff_lpf, \cutoff_hpf, \phase, \fold, \level, \pan, \sendA, \sendB],
				msg[2..]].lace;

				if (voxs[idx] != nil) {
					voxs[idx].free;
				};

				syn = Synth.new(
					\svDrm,
					args
					++ [
					\sendABus, (~sendA ? Server.default.outputBus),
					\sendBBus, (~sendB ? Server.default.outputBus)]
				);

				syn.onFree {
					if (voxs[idx] != nil && voxs[idx] === syn) {
						voxs.put(idx, nil);
					};
				};

				voxs.put(idx, syn);

			}, "/svdrm/trig");

		};
	}
}