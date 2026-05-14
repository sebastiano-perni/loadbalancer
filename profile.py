import geni.portal as portal
import geni.rspec.pg as pg

# Request the LAN
request = portal.context.makeRequestRSpec()
lan = request.LAN("lan")


# Helper function to generate a node
def add_node(name):
    node = request.RawPC(name)
    # Using a standard Ubuntu 22.04 image
    node.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"

    # Connect to the LAN
    iface = node.addInterface("if1")
    lan.addInterface(iface)

    # Execute the initialization script on boot
    node.addService(pg.Execute(shell="bash", command="/local/repository/cloudlab_setup.sh > /tmp/setup.log 2>&1"))
    return node


# 1. Telemetry Node
add_node("telemetry")

# 2. Client / Load Generator Node
add_node("client")

# 3. Load Balancers
add_node("lb-prequal")
add_node("lb-rr")

# 4. Backend Servers (13 nodes)
for i in range(1, 14):
    add_node("backend-%d" % i)

# Print the RSpec to the enclosing context
portal.context.printRequestRSpec()
