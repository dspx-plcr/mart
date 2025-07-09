use errors;
use fmt;
use fs;
use io;
use os;
use os::exec;
use strings;
use unix;

def N_STRATS: size = len(allstrats);
def allstrats: [_]str = [
	"Expected Return",
	"First Card, All In",
	"Random",
];

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

fn runproces(i: size, j: size, k: size, l: size) io::file = {
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

	const cmd = match (exec::cmd("./mart", "-n:100",
			s1, s2, s3, s4, log)) {
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
			"couldn't make pipe non blocking: {}",
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

export fn main() void = {
	let fds: [N_STRATS*N_STRATS*N_STRATS*N_STRATS]io::file = [0...];
	let pos = 0z;
	for (let i = 0z; i < N_STRATS; i += 1)
		for (let j = 0z; j < N_STRATS; j += 1)
			for (let k = 0z; k < N_STRATS; k += 1)
				for (let l = 0z; l < N_STRATS; l += 1) {
					fds[pos] = runproces(i, j, k, l);
					pos += 1;
				};

	for (true) {
		let waiting = false;
		for (let fd .. fds) {
			static let buf: [1024]u8 = [0...];
			const n = match (io::read(fd, buf)) {
				case let n: size => waiting = true; yield n;
				case io::EOF => yield 0z;
				case errors::again => yield 0z;
				case let e: io::error => fmt::fatalf(
					"couldn't read from buf: {}",
					io::strerror(e));
			};
			io::write(os::stdout, buf[..n]): void;
		};

		if (!waiting)
			break;
	};
};
