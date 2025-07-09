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

(defn process-message [msg]
  (print "read message: " msg))

(defn run-proc [{:id id :strats strats}]
  (def game-name (do
    (defn pad [str]
      (string str (string/repeat " " (- max-strat-len (length str)))))
    (string/join (map pad strats) " | ")))

  (def pipe (os/pipe :W))
  (def proc
    (try (os/spawn ["./mart"
             (string "-log:" (dyn :log-dir) "/" game-name)
             (string/format "-n:%d" (dyn :num-games))
             ;(map |(string "-strategy:" $) strats)]
           :x {:out (get pipe 1) :err :pipe})
      ([msg _] (error {:id id :err-type :spawn :err-msg msg}))))

  (def buf (buffer/new 1024))
  (var prev "")
  (while (-?>>
    (try (ev/read (get pipe 0) 1024 buf 0)
      ([msg _] (case msg
         "timeout" ""
         _  (error {:id id :err-type :read :err-msg msg}))))
    (string prev)
    (string/split "\n")
    |(tuple ;$)
    |(do (set prev (last $)) (tuple/slice $ 0 -2))
    |(each msg $ (process-message msg))))
  (if (not (empty? prev))
    (process-message prev))
  (os/proc-close proc)
  (ev/close (first pipe))
  (ev/close (last pipe)))

(cmd/main (cmd/fn
  [[num-games --n -n] (optional :int+ 100)
   [excluded --exclude-strategy] (tuple :string)]
  (set all-strats (filter |(not (has-value? excluded $)) all-strats))
  (def rng (math/rng (os/cryptorand 4)))
  (def dir (string "logs-" (string/format "%08X" (math/rng-int rng))))
  # TODO: returns false if dir already exists (do I want to do anything?)
  (try (os/mkdir dir)
   ([msg _]
    (eprint "couldn't create output directory " msg)
    (os/exit 1)))

  (setdyn :log-dir dir)
  (setdyn :num-games num-games)
  (def procs @{})
  (var id 0)
  (def ch (ev/chan))
  (each strats (coro (next-strat))
    (put procs id {
      :id id
      :fibre (ev/go (fiber/new run-proc :tp)
               {:strats strats
                :id id}
               ch)
      })
    (++ id))

  (var finished 0)
  (forever
    (def [status f] (ev/take ch))
    (if (= status :ok) (do
      (++ finished)
      (if (= finished (length procs)) (break)))))))
