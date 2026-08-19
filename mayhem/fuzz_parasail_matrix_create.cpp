#include <stdint.h>
#include <stdio.h>
#include <climits>

#include <fuzzer/FuzzedDataProvider.h>

extern "C" {
    #include "parasail.h"
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    FuzzedDataProvider provider(data, size);
    int match = provider.ConsumeIntegral<int>();
    int mismatch = provider.ConsumeIntegral<int>();
    std::string cigar = provider.ConsumeRemainingBytesAsString();

    parasail_matrix_t* matrix = parasail_matrix_create(cigar.c_str(), match, mismatch);
    parasail_matrix_free(matrix);
    return 0;
}
