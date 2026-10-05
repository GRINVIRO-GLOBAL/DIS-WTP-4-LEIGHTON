import asyncio
from pymodbus.server import StartAsyncTcpServer, StartAsyncSerialServer
from pymodbus.device import ModbusDeviceIdentification
from pymodbus.datastore import ModbusSequentialDataBlock, ModbusSlaveContext, ModbusServerContext

async def run_modbus_server():
    # 1. Inisialisasi Data / Register
    # Blok data diisi dengan nilai awal. Contoh di bawah membuat 100 register.
    store = ModbusSlaveContext(
        di=ModbusSequentialDataBlock(0, [0]*100),                   # Discrete Inputs (Read-only bool)
        co=ModbusSequentialDataBlock(0, [0]*100),                   # Coils (Read/Write bool)
        hr=ModbusSequentialDataBlock(0, [15, 30, 45, 60] + [0]*96), # Holding Registers (Read/Write int) - nilai awal: 15, 30, dst.
        ir=ModbusSequentialDataBlock(0, [0]*100)                    # Input Registers (Read-only int)
    )

    context = ModbusServerContext(slaves=store, single=True)

    # 2. Identitas Perangkat (Opsional)
    identity = ModbusDeviceIdentification()
    identity.VendorName = 'Laptop_Generator'
    identity.ProductCode = 'MB_Simulator'
    identity.ModelName = 'Python Modbus Node'
    identity.MajorMinorRevision = '1.0'

    # =========================================================================
    # 3. PILIH JALUR KOMUNIKASI (Uncomment salah satu yang ingin digunakan)
    # =========================================================================

    # OPSI A: Menggunakan Modbus TCP (Ethernet/LAN)
    # print("Menjalankan Modbus TCP Server di port 5020...")
    # await StartAsyncTcpServer(
    #     context=context, 
    #     identity=identity, 
    #     address=("0.0.0.0", 5020) # 0.0.0.0 artinya bisa diakses dari IP laptop Anda
    # )

    # OPSI B: Menggunakan Modbus RTU (Membutuhkan USB to RS-485)
    # Pastikan mengganti 'COM3' dengan port USB to RS485 di laptop Anda (atau '/dev/ttyUSB0' di Linux/Mac)
    print("Menjalankan Modbus RTU Server di port COM3...")
    await StartAsyncSerialServer(
        context=context, 
        identity=identity, 
        port='COM5', 
        baudrate=9600, 
        bytesize=8, 
        parity='N', 
        stopbits=1
    )

if __name__ == "__main__":
    try:
        asyncio.run(run_modbus_server())
    except KeyboardInterrupt:
        print("Server Modbus dimatikan.")