#include "razen_core.h"
#include <stdio.h>

int main() {
    printf("Razen Runtime Test\n");

    // 1. Test primitive types
    i32 a = -42;
    u32 b = 42;
    f32 c = 3.14f;
#if defined(__GNUC__) || defined(__clang__)
    i128 huge = 123456789;
#endif

    // 2. Test Slices
    SliceI32 numbers;
    numbers.ptr = &a;
    numbers.len = 1;

    // 3. Test Strings
    RazenStr s = { .ptr = (const uint8_t*)"Hello, Razen!", .len = 13 };
    printf("String: %.*s\n", (int)s.len, s.ptr);

    // 4. Test Allocator (@c)
    RazenAllocator* alloc = &builtin_c_allocator;
    
    // allocate 10 integers
    i32* arr = (i32*)alloc->alloc(alloc, 10 * sizeof(i32));
    arr[0] = a;
    arr[1] = (i32)b;
    
    printf("Allocated and set arr[0]=%d, arr[1]=%d\n", arr[0], arr[1]);

    // resize
    arr = (i32*)alloc->resize(alloc, arr, 10 * sizeof(i32), 20 * sizeof(i32));
    
    // free
    alloc->free(alloc, arr, 20 * sizeof(i32));

    // 5. Test Options
    OptionI32 opt1 = { .has_value = true, .value = 100 };
    OptionI32 opt2 = { .has_value = false, .value = 0 };

    if (opt1.has_value) printf("Option has value: %d\n", opt1.value);

    // 6. Test Error Unions
    ErrorUnionI32 res = { .error = RAZEN_OK, .value = 99 };
    if (res.error == RAZEN_OK) {
        printf("ErrorUnion is OK: %d\n", res.value);
    }

    // 7. Test RAZEN_TRY (GCC/Clang only inline test)
#if defined(__GNUC__) || defined(__clang__)
    // We can't return from main with an ErrorType easily if it doesn't match main's int signature,
    // so we won't test TRY inline here unless we create a helper function.
    printf("RAZEN_TRY macro is defined for GNUC/Clang.\n");
#endif

    printf("Test completed successfully.\n");
    return 0;
}
