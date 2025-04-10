cp programs/* ../proj3/programs/
cd ../proj3
make simulate_all -j$(nproc)

cd ../csee4824-final-project/
cp ../proj3/output/* correct_out/
rm correct_out/*.ppln

