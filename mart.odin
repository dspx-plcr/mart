package main

import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:os"
import "core:sort"
import "core:strings"

Options :: struct {
	log_path: string `args:"name=log"`,
	logger: runtime.Logger `args:"hidden"`,
	n: uint,
	strats: [dynamic]Strategy `args:"name=strategy,required=4<5"`,
}

Auction :: enum { Open, Offer, Secret, Fixed, Double }
auction_names := [Auction]string {
	.Open = "open",
	.Offer = "single offer",
	.Secret = "secret",
	.Fixed = "fixed price",
	.Double = "double auction",
}

Artist :: struct {
	name: string,
	cards: [Auction]uint,
}

Card :: struct {
	id: uint,
	type: Auction,
	artist: uint,
	public: bool,
}

Player :: struct {
	id: uint,
	cards: [dynamic]Card,
	bought: []uint,
	money: int,
	strat: Strategy,
}

Bid_Event :: struct {
	player: uint,
	amount: int,
}

Pass_Event :: struct {
	player: uint,
}

Win_Event :: struct {
	player: uint,
	amount: int,
	auction: Auction_Event,
}

Round_End_Event :: struct {}

Auction_Event :: struct {
	player: uint,
	card: uint,
	double: uint,
	is_double: bool,
	price: int,
}

Resource_Event :: struct {
	cards: []uint,
	money: int,
}

Event :: union {
	Bid_Event,
	Pass_Event,
	Win_Event,
	Round_End_Event,
	Auction_Event,
	Resource_Event,
}

state: struct {
	deck: []Card,
	pos: uint,
	round: uint,
	auctioneer: uint,
	artists: []Artist,
	schedule: ^Deal_Schedule,
	reward_base: []int,
	reward: []int,
	round_played: []uint,
	players: []Player,
	events: [dynamic]Event,
}

find_card_num :: proc(player: Player, card: uint) -> (uint, bool) {
	for c, i in player.cards {
		if c.id == card {
			return uint(i), true
		}
	}

	return uint(0), false
}

card_str :: proc(card_id: uint) -> string {
	if card_id >= len(state.deck) {
		return fmt.aprintf("<<invalid id %d>>", card_id)
	}
	card := state.deck[card_id]
	return fmt.aprintf("%d %s (%s)", card_id,
		state.artists[card.artist].name, auction_names[card.type])
}

// TODO: make this robust against querying cards that aren't ours
get_card :: proc(card_id: uint) -> Card {
	for c in state.deck {
		if c.id == card_id {
			return c
		}
	}

	return Card{}
}

opt_parser :: proc (
	data: rawptr,
	data_type: typeid,
	stream: string,
	tag: string,
) -> (
	error: string,
	handled: bool,
	alloc_error: runtime.Allocator_Error
) {
	if data_type == Strategy {
		handled = true
		ptr := cast(^Strategy) data
		first := true
		msg, _ := strings.builder_make()
		strings.write_string(&msg, "Unknown strategy.")
		for s in strategies {
			if stream == s.name {
				ptr^ = s.value
				strings.builder_destroy(&msg)
				return
			}

			if first {
				strings.write_string(&msg, " Must be one of ")
				first = false
			} else {
				strings.write_string(&msg, ", ")
			}
			strings.write_byte(&msg, '`')
			strings.write_string(&msg, s.name)
			strings.write_byte(&msg, '`')
		}

		error = strings.to_string(msg)
	}

	return
}

opt_validator :: proc (
	model: rawptr,
	name: string,
	value: any,
	arg_tags: string,
) -> (error: string) {
	opts := cast(^Options) model
	if name == "log_path" {
		v := value.(string)
		if v == "" {
			opts.logger = log.nil_logger()
			return
		}

		fd: os.Handle
		if v == "-" {
			fd = os.stdin
		} else {
			handle, err := os.open(v,
				flags = os.O_CREATE | os.O_RDWR | os.O_TRUNC,
				mode = 0o664)
			if err != os.ERROR_NONE {
				return "couldn't open log file"
			}
			fd = handle
		}

		log_opts := bit_set[runtime.Logger_Option] { .Level }
		opts.logger = log.create_file_logger(fd, opt = log_opts)
	}

	return
}

main :: proc() {
	opts: Options
	flags.register_type_setter(opt_parser)
	flags.register_flag_checker(opt_validator)
	flags.parse_or_exit(&opts, os.args, .Odin)
	defer if opts.log_path != "" do log.destroy_file_logger(opts.logger)

	// TODO: remove this and do actual stats
	context.logger = opts.logger
	wins := make([]uint, len(opts.strats))
	for i in 1..=opts.n {
		setup_game(mart_conf, opts.strats[:]);
		play_game()
		sort.merge_sort_proc(state.players, proc(p, q: Player) -> int {
			return q.money - p.money
		})

		winner := state.players[0]
		wins[winner.id] += 1
		fmt.printfln("%d,%d,%d", winner.id, winner.money,
			winner.money - state.players[1].money)
		packup_game()
	}

	for w, i in wins {
		log.infof("Player %d won %d times", i, w)
	}
}
