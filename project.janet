(declare-project
  :name "runner"
  :description "a runner"
  :dependencies [
    {:url "https://github.com/ianthehenry/cmd.git"
     :tag "v1.1.0"}
  ])

(declare-executable
  :name "runner"
  :entry "runner.janet")
