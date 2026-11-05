/*
 * Lab: Response Cache for an LLM Service (Hashing with Separate Chaining)
 *
 * Starter code. Read the problem statement before you begin.
 *
 * What is already done for you:
 *   - the data structures (Node and HashTable)
 *   - the hash function hash_fingerprint()
 *   - reading the input and printing every response in main()
 *
 * What you must implement (search for "TODO"):
 *   create_table, search, store, mostpop, dump_bucket, free_table
 *   The bodies are empty. The only lines inside them are placeholder
 *   return statements that let this file compile; replace them.
 *
 * Rules:
 *   - Do not change the function signatures or main().
 *   - Store fingerprints only in the chains of the hash table.
 *   - Compile with:  gcc -O2 -Wall -o llm_cache llm_cache_starter.c
 *   - Run with:      ./llm_cache < input.txt
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* Data structures                                                     */
/* ------------------------------------------------------------------ */

/* One cached fingerprint in a chain (singly linked list). */
typedef struct Node {
    int fp;               /* fingerprint, 1 <= fp <= 10^7 */
    struct Node *next;    /* next node in the same bucket, or NULL */
} Node;

/* The cache index. */
typedef struct {
    Node **buckets;       /* array of m chain heads; buckets[b] == NULL if empty */
    int m;                /* number of buckets (fixed) */
} HashTable;

/* ------------------------------------------------------------------ */
/* Hash function (complete, do not modify)                             */
/* ------------------------------------------------------------------ */

/*
 * Returns the bucket for fingerprint fp in a table with m buckets.
 * Fingerprints are positive, so fp % m is always in the range 0 .. m-1.
 * Use only this function to choose a bucket: the expected output depends on it.
 */
int hash_fingerprint(int fp, int m) {
    return fp % m;
}

/* ------------------------------------------------------------------ */
/* Functions to implement                                              */
/* ------------------------------------------------------------------ */

/*
 * Creates an empty table with m buckets (all chains empty).
 */
HashTable *create_table(int m) {
    /* TODO: write your code here */

    return NULL;   /* placeholder: replace with your table */
}

/*
 * Searches the chain of fp from the head.
 * Sets *comparisons to the number of fingerprints compared with fp:
 *   - if fp is the c-th node in its chain, *comparisons = c
 *   - if fp is not present, *comparisons = length of the chain
 * Returns 1 if fp is cached, 0 otherwise. Must not change the chain.
 */
int search(HashTable *t, int fp, int *comparisons) {
    /* TODO: write your code here */

    return 0;      /* placeholder */
}

/*
 * Caches fingerprint fp.
 *   - If fp is already cached, return 0 and leave the table unchanged.
 *   - Otherwise insert fp at the HEAD of its chain and return 1.
 */
int store(HashTable *t, int fp) {
    /* TODO: write your code here */

    return 0;      /* placeholder */
}

/*
 * Finds the bucket with the longest chain.
 * Sets *bucket and *length. On a tie, choose the smallest bucket index.
 * If the table is empty, *bucket = 0 and *length = 0.
 */
void mostpop(HashTable *t, int *bucket, int *length) {
    /* TODO: write your code here */

}

/*
 * Prints the fingerprints in bucket b from head to tail on one line,
 * separated by single spaces, followed by a newline.
 * Prints "EMPTY" (and a newline) if the bucket is empty.
 */
void dump_bucket(HashTable *t, int b) {
    /* TODO: write your code here */

}

/*
 * Frees every node, the bucket array and the table itself.
 */
void free_table(HashTable *t) {
    /* TODO: write your code here */

}

/* ------------------------------------------------------------------ */
/* Input / output (complete, do not modify)                            */
/* ------------------------------------------------------------------ */

int main(void) {
    int m, q;
    if (scanf("%d %d", &m, &q) != 2) return 0;

    HashTable *t = create_table(m);
    char req[16];
    int x, c = 0;

    for (int i = 0; i < q; i++) {
        if (scanf("%15s", req) != 1) break;

        if (strcmp(req, "MOSTPOP") == 0) {
            int b = 0, len = 0;
            mostpop(t, &b, &len);
            printf("MOSTPOP %d %d\n", b, len);
            continue;
        }

        if (scanf("%d", &x) != 1) break;

        if (strcmp(req, "STORE") == 0) {
            if (store(t, x)) printf("STORED %d\n", x);
            else printf("DUPLICATE %d\n", x);
        } else if (strcmp(req, "LOOKUP") == 0) {
            int found = search(t, x, &c);
            printf("%s %d\n", found ? "HIT" : "MISS", c);
        } else if (strcmp(req, "DUMP") == 0) {
            dump_bucket(t, x);   /* here the number read is the bucket index */
        }
    }

    free_table(t);
    return 0;
}
