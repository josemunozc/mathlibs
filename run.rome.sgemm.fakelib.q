#!/bin/bash --login
#SBATCH -J mt-sgemm-icc
#SBATCH -o o.%x.rome.%j
#SBATCH -e e.%x.rome.%j
#SBATCH --ntasks=64
#SBATCH --ntasks-per-node=64 # tasks to run per node
#SBATCH -p xcompute_amd
#SBATCH --time=00:15:00
#SBATCH --exclusive
#SBATCH -A scw1001

set -eu

buildflavors[0]="compiler/intel/2018/2 mkl/2018/2" 
buildflavors[1]="compiler/intel/2020/0 mkl/2020/0" 
buildflavors[2]="compiler/intel/2020/1 mkl/2020/1" 

for i in `seq 1 ${#buildflavors[@]}`;
do
    flavor=${buildflavors[$((i-1))]}
    module purge
    module load $flavor
    module list
    echo "Using modules: " $flavor
    MKL_VERSION=`echo $MKLROOT | cut -d/ -f5`
    echo "MKL Version: " $MKL_VERSION

    export OMP_NUM_THREADS=1

    case $MKL_VERSION in
        2018.2)
            unset MKL_CBWR
            unset MKL_DEBUG_CPU_TYPE
            unset MKL_ENABLE_INSTRUCTIONS

            export MKL_CBWR=AVX2
            export MKL_DEBUG_CPU_TYPE=5
            #export MKL_ENABLE_INSTRUCTIONS=AVX2 # not defined in 2018.2
          ;;
        2020.0)
            unset MKL_CBWR
            unset MKL_DEBUG_CPU_TYPE
            unset MKL_ENABLE_INSTRUCTIONS

            export MKL_CBWR=AVX2
            export MKL_DEBUG_CPU_TYPE=5
            export MKL_ENABLE_INSTRUCTIONS=AVX2
          ;;
        2020.1)
            unset MKL_CBWR
            unset MKL_DEBUG_CPU_TYPE
            unset MKL_ENABLE_INSTRUCTIONS

            #export MKL_CBWR=COMPATIBLE # Used in 2020.2 but AVX2 causes "Illegal instruction" error
            export MKL_DEBUG_CPU_TYPE=5 # not present in 2020.1
            export MKL_ENABLE_INSTRUCTIONS=AVX2
          ;;
        *)
            echo -n "unknown MKL version $MKL_VERSION"
            exit 1
          ;;
    esac

    env | grep SCW
    env | grep MKL
    env
    
    ######################
    #    setup paths     #
    ######################
    input_dir=$HOME/mkl-test/mt-dgemm/src
    output_dir=$SLURM_SUBMIT_DIR/output.rome/$MKL_VERSION
    code_src=mt-sgemm.c
    code_exe=mt-sgemm-icc
    make_file=Makefile.intel.hawk
    
    mkdir -p $output_dir
    
    ######################
    # remove older files #
    # if present         #
    ######################
    rm -f $code_exe
    rm -f libfakeintel.so
    
    ########################
    # compile bench test   #
    ########################
    cp $input_dir/$make_file .
    cp $input_dir/$code_src .
    make -f $make_file clean
    make -f $make_file $code_exe
    
    ########################
    # compile fake lib and #
    # add to path      #
    ########################
    echo "compiling fake MKL lib"
    gcc -shared -fPIC -o libfakeintel.so fakeintel.c
    root=`pwd`
    export LD_PRELOAD=$root/libfakeintel.so
    
    ########################
    # run bench test       #
    ########################
    N=4000
    for omp in 1 2 4 8 16 32 64;
    do
        export OMP_NUM_THREADS=$omp
        echo OMP_NUM_THREADS=$OMP_NUM_THREADS
    
        perf record -e cpu-cycles -o $output_dir/perf.data.omp$omp ./$code_exe $N
        perf report --stdio -i $output_dir/perf.data.omp$omp > $output_dir/perf.report.omp$omp
    done
    
    ########################
    # run one more time to #
    # check environment    #
    ########################
    export OMP_NUM_THREADS=64
    ltrace -e getenv ./$code_exe 128 2>&1

done
