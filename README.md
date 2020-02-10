SimplePool
================

**SimplePool** provides scaffolding for working with long lived distributed worker processes. 
SimplePool library has been highly optimized to work at scale and is capable of managing millions 
of frequently accessed long lived processes, while exposing the ability for developers to override 
internal behavior as needed by their individual projects or for specific worker types.    

**SimplePool** provides support for 
- monitoring services (failures per minute, etc.)
- distributing load across a cluster.
- counting workers across the distributed cluster.
- checking process (alive/dead) across the distributed cluster.
- rapid worker to node/process resolution.
- enhanced message passing and processing including support for rerouting during worker migration or respawn.
- lazy, asynchronous or sychronous pool worker spawning. 
- support for rebalancing workers across cluster (with per node target support)
- support for offloading (deprovisioning) service(s) on a specific node for maintenance/upgrades.
- automatic inactive process offloading. 
- target level based load balancing of new workers across cluster.

What is it for?
----------------------------
Representing NPCs, Users, ChatRooms, IOT Devices where individual workers need to frequently respond to requests or perform background heart beat tasks.  
(Additional Documentation Pending)


Key Components and Terms
----------------------------
(Additional Documentation Pending)

### Pool
A pool of long lived processes.

### Pool.Worker
Wrapper around user provided entities that implement the InnerStateBehaviour. Manages automatic deprovisioning, initilization handling, message routing, other maintenance tasks.

### Pool.Server
Responsible for forwarding requests to underling messages. To avoid cpu bottle necks worker spawning and pid lookup along with most calls
are performed within calling thread (or off process spawn). 

### Pool.PoolSupervisor
Top node in pool's OTP tree.

### Pool.WorkerSupervisor
Manages Layer2 Worker Supervisor Segments 

### Pool.WorkerSupervisor.Seg\[0-n\]
Layer 2 of the Pool.WorkerSupervisor node. Per process compile time settings and run time options control how many supervisors are spawned. 
The large number of Segments coupled with fragmented Dispatch workers help to avoid per supervisor bottlenecks when rapidly spawning hundreds of thousands of workers on initial start.


Version 2 
----------------------------
The SimplePool Library includes two alternative implementations. 
To allow gradual migration of Pools from the previous implementation to the new implementation on existing projects. 

Version2 libraries take advantage of newer Elixir features and seeks to reduce some of the compile time overhead introduced
by the forced recompiles caused from heavy reliance of interconnected modules and metaprogramming. 
Version2 additionally relies on ElixirScaffolding.V2 entity/repo types with the same considerations in mind.  


How it Works
----------------------------
(Additional Documentation Pending)

What Happens Behind The Scenes
----------------------------
(Additional Documentation Pending)


Example
----------------------------
See test/support/v2/services/test_pool for an example of a simple server/worker setup.

```
 # Code Snippets Pending
```

Running Test Suite
----------------------------
Because SimplePool coordinates activites between multiple nodes the test suite requires some additional steps to run. 
To run the suite first launch the second node using `./test-node.sh` then in a second console window launch the actual suite with `./run-test.sh`.


Related Technology
---------------------------
- [ElixirScaffolding](https://github.com/noizu/ElixirScaffolding) - This library provides scaffolding for working with DomainObjects and Repos, access control, and including unique identifer ref tuples and protocols for converting between domain objects and ref tuples or vice versa.
- [ElixirCore](https://github.com/noizu/ElixirCore) - Support for tracking call context between layers.  Entity Reference Protocols, OptionHelper support for compile time options with defaults/and required field type and presence validation. 
- [MnesiaVersioning](https://github.com/noizu/MnesiaVersioning) - Simple Change Management Library for Mnesia/Amnesia. 
- [KitchenSink](https://github.com/noizu/KitchenSink) - Various useful libraries and tools that integrate with SimplePool and ElixirScaffolding. (CMS, Transactional Emails, SmartTokens, ...)
- [RuleEngine](https://github.com/noizu/RuleEngine) - Extensible DB Driven Scripting/RuleEngine Library. 



Additional Documentation
----------------------------
* [Api Documentation](http://noizu.github.io/SimplePool)
