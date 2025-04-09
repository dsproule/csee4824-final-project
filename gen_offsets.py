offs = [8, 16, 32]

print('case (S_X_reg.mem_size)')
for off in offs:
    ind = '    '
    if off == 8:
        print(f'{ind}BYTE: begin\n{ind}{ind}shift = (line_offset) << 3;')
    elif off == 16:
        print(f'{ind}HALF: begin\n{ind}{ind}shift = (line_offset >> 1) << 4;')
    elif off == 32:
        print(f'{ind}WORD: begin\n{ind}{ind}shift = (line_offset[2] << 2) << 3;')

    print(f'{ind}{ind}case (shift)')
    for i in range(0, 63, off):
        print(f'{ind}{ind}{ind}{i}: Dmem_data[{off + i - 1}:{i}] = S_X_reg.V2[{off - 1}:0];')
    print(f'{ind}{ind}endcase\n{ind}end')
print(f'{ind}default: begin\n{ind}{ind}shift = \'0;\n{ind}{ind}size_offset = \'0;\n{ind}end\nendcase')
