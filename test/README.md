Test Notes
----------------------------------------

Because Simple pool deals with distributed system calls to running 
the acceptance test suite requires that more than one node is started.

To launch the second node invoke `./test-node.sh`
this will start a node names second as follows: 
```
MIX_ENV=test iex --no-halt --name second@127.0.0.1 --cookie apple -S mix second_test_node
```

After launching the test node in a different terminal window run `./run-test.sh` or 
if you wish to specify specific suites `MIX_ENV=test iex --no-halt --name first@127.0.0.1 --cookie apple -S mix test --only v2`
After tests run you will remain in the instance and may run additional manual tests or inspect pool state.

You will need to restart both nodes every time you re-run tests. 
run-test.sh will stall during setup if tests have already run against the node started by test-node.sh

Happy Testing!