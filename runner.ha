use errors;
use fmt;
use fs;
use getopt;
use io;
use os;
use os::exec;
use strconv;
use strings;
use types;
use types::c;
use unix;
use unix::poll;

let allstrats: [_]str = [
	"Expected Return",
	"First Card, All In",
	"Random",
];

let numgames: size = 0;

fn gamename(s1: const str, s2: const str, s3: const str, s4: const str) str = {
	static let maxlen = 0z;
	if (maxlen == 0)
		for (let s .. allstrats)
			if (len(s) > maxlen)
				maxlen = len(s);

	const pads1 = match (strings::rpad(s1, ' ', maxlen)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};
	defer free(pads1);
	const pads2 = match (strings::rpad(s2, ' ', maxlen)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};
	defer free(pads2);
	const pads3 = match (strings::rpad(s3, ' ', maxlen)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};
	defer free(pads3);
	const pads4 = match (strings::rpad(s4, ' ', maxlen)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};
	defer free(pads4);

	const res = match (strings::join(" | ", pads1, pads2, pads3, pads4)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};

	return res;
};

fn runprocess(
	gname: const str,
	s1: const str,
	s2: const str,
	s3: const str,
	s4: const str,
) io::file = {
	const args1 = match (strings::concat("-strategy:", s1)) {
		case nomem => fmt::fatal("couldn't alloc strategy: nomem");
		case let s: str => yield s;
	};
	defer free(args1);
	const args2 = match (strings::concat("-strategy:", s2)) {
		case nomem => fmt::fatal("couldn't alloc strategy: nomem");
		case let s: str => yield s;
	};
	defer free(args2);
	const args3 = match (strings::concat("-strategy:", s3)) {
		case nomem => fmt::fatal("couldn't alloc strategy: nomem");
		case let s: str => yield s;
	};
	defer free(args3);
	const args4 = match (strings::concat("-strategy:", s4)) {
		case nomem => fmt::fatal("couldn't alloc strategy: nomem");
		case let s: str => yield s;
	};
	defer free(args4);
	const log = match (strings::concat("-log:logs/", gname)) {
		case nomem => fmt::fatal("couldn't alloc strategy: nomem");
		case let s: str => yield s;
	};
	defer free(log);
	const n = match (fmt::asprintf("-n:{}", numgames)) {
		case nomem => fmt::fatal("couldn't alloc num games: nomem");
		case let s: str => yield s;
	};
	defer free(n);

	const cmd = match (exec::cmd("./mart", n, log,
			args1, args2, args3, args4)) {
		case let cmd: exec::command => yield cmd;
		case nomem => fmt::fatal("couldn't create command: no memory");
		case let e: exec::error =>
			fmt::fatalf("couldn't create command: {}",
				exec::strerror(e));
	};

	const (rd, wr) = match (unix::pipe()) {
	case let res: (io::file, io::file) => yield res;
	case let e: errors::error =>
		fmt::fatalf("couldn't create pipe: {}", errors::strerror(e));
	};

	match (os::setflags(rd, fs::flag::NONBLOCK)) {
		case void => yield;
		case let e: errors::error => fmt::fatalf(
			"couldn't set pipe as non-blocking: {}",
			errors::strerror(e));
	};

	match (exec::addfile(&cmd, os::stdout_file, wr)) {
		case nomem => fmt::fatalf("couldn't redirect child out: nomem");
		case void => yield;
	};
	let proc = match (exec::start(&cmd)) {
		case let p: exec::process => yield p;
		case let e: exec::error =>
			fmt::fatalf("couldn't launch process: {}",
				exec::strerror(e));
	};
	io::close(wr): void;

	return rd;
};

type stats = opaque;
@symbol("st_plot") fn stats_plot(*stats) int;
@symbol("st_new") fn newstats(const *c::char) nullable *stats;
@symbol("st_input") fn stats_input(*stats, nullable *const u8, size) int;
export fn main() void = {
	const cmd = getopt::parse(os::args,
		"modert art of command runners",
		('n', "num", "number of games for each pairing"),
		('e', "strategy", "strategy to exclude from the pairings"),
	);
	defer getopt::finish(&cmd);

	let excluded: []str = [];
	for (let opt .. cmd.opts) {
		switch (opt.0) {
		case 'n' => numgames = match (strconv::stoz(opt.1)) {
			case let n: size => yield n;
			case let e: strconv::error =>
				fmt::fatalf("couldn't parse -n {}: ",
					strconv::strerror(e));
			};
		case 'e' => match (append(excluded, opt.1)) {
			case void => yield;
			case nomem => fmt::fatalf(
				"couldn't record excluded strat {}: no memory",
				opt.1);
			};
		case => fmt::fatal("internal error: unknown opt");
		};
	};

	let numstrats: size = len(allstrats);
	for (let s .. excluded) {
		let found = false;
		for (let i = 0z; i < numstrats; i += 1)
			if (s == allstrats[i]) {
				found = true;
				allstrats[i] = allstrats[numstrats-1];
				numstrats -=1;
				break;
			};
		if (!found)
			fmt::errorf(
				"unrecognised excluded strategy: {}", s): void;	
	};
	for (let i = 0z; i < numstrats; i += 1)
		for (let s .. excluded)
			if (s == allstrats[i]) {
				allstrats[i] = allstrats[numstrats-1];
				i -= 1;
				numstrats -= 1;
			};

	const numfds: size = numstrats*numstrats*numstrats*numstrats;
	def evs: i16 = poll::event::POLLIN | poll::event::POLLPRI;
	let pfds = match (alloc([]: []poll::pollfd, numfds)) {
		case let ps: []poll::pollfd => yield ps;
		case nomem => fmt::fatal("couldn't alloc for fds: nomem");
	};
	let sts = match (alloc([]: []*stats, numfds)) {
		case let ss: []*stats => yield ss;
		case nomem => fmt::fatal("couldn't alloc for stats: nomem");
	};
	let pfdtost = match (alloc([]: []size, numfds)) {
		case let ps: []size => yield ps;
		case nomem => fmt::fatal("couldn't alloc for mapping: nomem");
	};
	defer free(pfds);

	const ns2 = numstrats * numstrats;
	const ns3 = ns2 * numstrats;
	for (let n = 0z; n < numfds; n += 1) {
		let l: size = n % numstrats;
		let k: size = (n / numstrats) % numstrats;
		let j: size = (n / ns2) % numstrats;
		let i: size = (n / ns3) % numstrats;

		const s1 = allstrats[i];
		const s2 = allstrats[j];
		const s3 = allstrats[k];
		const s4 = allstrats[l];
		const gname = gamename(s1, s2, s3, s4);
		let name = match (fmt::asprintf("out/{}.svg\0", gname)) {
			case nomem => fmt::fatal(
				"couldn't alloc for game name: nomem");
			case let gn: str => yield gn;
		};

		append(pfds, poll::pollfd {
			fd = runprocess(gname, s1, s2, s3, s4),
			events = evs,
			revents = 0,
		}): void;
		append(pfdtost, n): void;
		append(sts, match (newstats(c::nulstr(name))) {
			case null => fmt::fatal("couldn't alloc stats: nomem");
			case let s: *stats => yield s;
		}): void;
	};

	for (len(pfds) > 0) {
		match (poll::poll(pfds)) {
			case let e: poll::error => fmt::fatalf(
				"couldn't poll fds: {}", poll::strerror(e));
			case let n: uint => if (n == 0) continue;
		};

		for (let i = 0z; i < len(pfds); i += 1) {
			const pfd = pfds[i];
			const evs = pfd.revents;
			if (evs & poll::event::POLLERR != 0)
				fmt::fatal("couldn't poll bufs: unknown error");

			static let buf: [1024]u8 = [0...];
			const n: size = match (io::read(pfd.fd, buf)) {
				case let n: size => yield n;
				case errors::again => continue;
				case io::EOF =>
					delete(pfds[i]);
					delete(pfdtost[i]);
					i -= 1;
					continue;
				case let e: io::error => fmt::fatalf(
					"couldn't read from buf: {}",
					io::strerror(e));
			};

			const st = sts[pfdtost[i]];
			const c = stats_input(st, &buf[0], n);
			switch (c) {
			case 0 => void;
			case => fmt::fatalf(
				"failed to update stats with `{}`",
				c);
				//strings::fromutf8_unsafe(buf[..n]));
			};
		};
	};

	for (let s .. sts)
		stats_plot(s);
};
