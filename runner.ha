use errors;
use fmt;
use fs;
use getopt;
use io;
use os;
use os::exec;
use strconv;
use strings;
use unix;
use unix::poll;

let allstrats: [_]str = [
	"Expected Return",
	"First Card, All In",
	"Random",
];

let numgames: size = 0;

fn gamename(i: size, j: size, k: size, l: size) str = {
	static let maxlen = 0z;
	if (maxlen == 0)
		for (let s .. allstrats)
			if (len(s) > maxlen)
				maxlen = len(s);

	const s1 = match (strings::rpad(allstrats[i], ' ', maxlen)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};
	defer free(s1);
	const s2 = match (strings::rpad(allstrats[j], ' ', maxlen)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};
	defer free(s2);
	const s3 = match (strings::rpad(allstrats[k], ' ', maxlen)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};
	defer free(s3);
	const s4 = match (strings::rpad(allstrats[l], ' ', maxlen)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};
	defer free(s4);

	const res = match (strings::join(" | ", s1, s2, s3, s4)) {
		case nomem => fmt::fatal("couldn't allocate game name: nomem");
		case let s: str => yield s;
	};

	return res;
};

fn runprocess(i: size, j: size, k: size, l: size) io::file = {
	const s1 = match (strings::concat("-strategy:", allstrats[i])) {
		case nomem => fmt::fatal("couldn't alloc strategy: nomem");
		case let s: str => yield s;
	};
	defer free(s1);
	const s2 = match (strings::concat("-strategy:", allstrats[j])) {
		case nomem => fmt::fatal("couldn't alloc strategy: nomem");
		case let s: str => yield s;
	};
	defer free(s2);
	const s3 = match (strings::concat("-strategy:", allstrats[k])) {
		case nomem => fmt::fatal("couldn't alloc strategy: nomem");
		case let s: str => yield s;
	};
	defer free(s3);
	const s4 = match (strings::concat("-strategy:", allstrats[l])) {
		case nomem => fmt::fatal("couldn't alloc strategy: nomem");
		case let s: str => yield s;
	};
	defer free(s4);
	const log = match (strings::concat("-log:logs/",
			gamename(i, j, k, l))) {
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
			s1, s2, s3, s4)) {
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

@symbol("st_plot") fn st_plot() int;
export fn main() void = {
	if (st_plot() < 0)
		fmt::fatal("couldn't plot");

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
	let pfds: []poll::pollfd = match (alloc([]: []poll::pollfd, numfds)) {
		case let ps: []poll::pollfd => yield ps;
		case nomem => fmt::fatal("couldn't alloc for fds: nomem");
	};
	defer free(pfds);
	for (let i = 0z; i < numstrats; i += 1)
		for (let j = 0z; j < numstrats; j += 1)
			for (let k = 0z; k < numstrats; k += 1)
				for (let l = 0z; l < numstrats; l += 1) {
					append(pfds, poll::pollfd {
						fd = runprocess(i, j, k, l),
						events = evs,
						revents = 0,
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
				case errors::again => yield 0;
				case io::EOF =>
					delete(pfds[i]);
					i -= 1;
					continue;
				case let e: io::error => fmt::fatalf(
					"couldn't read from buf: {}",
					io::strerror(e));
			};
			io::write(os::stdout, buf[..n]): void;
		};
	};
};
