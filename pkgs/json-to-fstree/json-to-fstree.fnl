(local json (require :json))
(local http (require :fetch))
(local svc (require :anoia.svc))
(local { : setenv : utime } (require :lualinux))

(fn download [url dest]
  (let [state (.. dest "/.outputs/state")
        previously (ll.lstat state 12)]
    (setenv "HTTP_ACCEPT" "application/json")
    (match (http.fetch url "i" previously)
      (nil 10 _) ; not modified
      (print (.. url " not modified, already up to date"))

      (nil code str)
      (assert nil (.. "error " code ": " str))

      (body { : last-modified })
      (let [service (svc.open dest)
            lock (.. dest "/.outputs/.lock")]
        (with-open [fout (io.open lock :w)] (fout:write ""))
        (service:output "." (json.decode body))
        ;; publish state through the service (which leaves an unchanged
        ;; file alone) instead of rewriting it on every pass
        (service:output "state" "ok")
        (utime state last-modified)
        (os.remove lock))

      )))

(fn run [] (download (. arg 1) (. arg 2)))


{ : run }
