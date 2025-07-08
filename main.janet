(import cmd)

(var all-strats [
  "First Card, All In"
  "Random"
  "Expected Return"
])

(def max-strat-len (max ;(map length all-strats)))

(defn next-strat []
  (each s1 all-strats
    (each s2 all-strats
      (each s3 all-strats
        (each s4 all-strats
          (yield [s1 s2 s3 s4]))))))

(defn finalise [&keys {:proc proc :strats strats}]
  (def game-name (do
    (defn pad [str]
      (string/join [str (string/repeat " " (- max-strat-len (length str)))]))
    (string/join (map pad strats) " | ")))
  (def path (string/join [(dyn 'out-dir) game-name] "/"))
  (def out-file
    (try (os/open path :wct 8r664)
      ([_ _]
       (eprint "couldn't write output statistics for " game-name) (break))))
  (try (os/proc-wait proc)
   ([err _]
    (eprint "TODO: return value (spawn fail vs proc fail): " err)))
  (def data
    (try (ev/read (proc :out) :all)
     ([msg _] (eprint "couldn't read from proc: " msg) (break))))
  (try (ev/write out-file data)
    ([err _] (eprint "TODO: return value: " err) (break)))
  (os/proc-close proc))

(cmd/main (cmd/fn
  [[num-games --n -n] (optional :int+ 100)
   [excluded --exclude-strategy] (tuple :string)]
  (set all-strats (filter |(not (has-value? excluded $)) all-strats))
  (def rng (math/rng (os/cryptorand 4)))
  (def dir (string/join ["output-" (string/format "%08X" (math/rng-int rng))]))
  # TODO: returns false if dir already exists (do I want to do anything?)
  (try (os/mkdir dir)
   ([msg _]
    (eprint "couldn't create output directory " msg)
    (os/exit 1)))

  (def procs @[])
  (each strats (coro (next-strat))
    (def proc (os/spawn
      ["./mart"
        (string/format "-n:%d" num-games)
        ;(map |(string/join ["-strategy:" $]) strats)]
      :x {:out :pipe :err :pipe}))
    (array/push procs {:proc proc :strats strats}))

  (setdyn 'out-dir dir)
  (each proc procs (finalise ;(kvs proc)))))
