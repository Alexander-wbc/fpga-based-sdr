transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+sync_fifo_32x128  -L xpm -L fifo_generator_v13_2_10 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.sync_fifo_32x128 xil_defaultlib.glbl

do {sync_fifo_32x128.udo}

run 1000ns

endsim

quit -force
