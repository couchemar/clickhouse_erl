%% @doc ClickHouse error codes and descriptions.
%%
%% This module provides constants and descriptions for ClickHouse error codes
%% as defined in the ClickHouse ErrorCodes.cpp file.
-module(clickhouse_erl_error_codes).

%% Public API
-export([
    get_error_code_description/1,
    get_readable_error/1,
    get_error/1
]).

%% Export types
-export_type([error_code/0, error_atom/0, error_description/0]).

%% Type definitions
-type error_code() :: integer().
-type error_atom() :: atom().
-type error_description() :: string().

%% Function specifications
-spec get_error_code_description(error_code()) -> {error_atom(), error_description()}.
-spec get_error(error_code()) -> error_atom().
-spec get_readable_error(error_code()) -> error_description().

%% Common ClickHouse error codes (from ErrorCodes.cpp)
%% Core errors
-define(UNSUPPORTED_METHOD, 1).
-define(UNSUPPORTED_PARAMETER, 2).
-define(UNEXPECTED_END_OF_FILE, 3).
-define(EXPECTED_END_OF_FILE, 4).
-define(CANNOT_PARSE_TEXT, 6).
-define(INCORRECT_NUMBER_OF_COLUMNS, 7).
-define(THERE_IS_NO_COLUMN, 8).
-define(SIZES_OF_COLUMNS_DOESNT_MATCH, 9).
-define(LOGICAL_ERROR, 10).
-define(DUPLICATE_COLUMN, 15).
-define(NO_SUCH_COLUMN_IN_TABLE, 16).
-define(SIZE_OF_FIXED_STRING_DOESNT_MATCH, 19).
-define(NUMBER_OF_COLUMNS_DOESNT_MATCH, 20).

%% Parsing and data errors
-define(CANNOT_READ_FROM_ISTREAM, 23).
-define(CANNOT_WRITE_TO_OSTREAM, 24).
-define(CANNOT_PARSE_ESCAPE_SEQUENCE, 25).
-define(CANNOT_PARSE_QUOTED_STRING, 26).
-define(CANNOT_PARSE_INPUT_ASSERTION_FAILED, 27).
-define(CANNOT_PRINT_FLOAT_OR_DOUBLE_NUMBER, 28).
-define(ATTEMPT_TO_READ_AFTER_EOF, 32).
-define(CANNOT_READ_ALL_DATA, 33).
-define(TOO_MANY_ARGUMENTS_FOR_FUNCTION, 34).
-define(TOO_FEW_ARGUMENTS_FOR_FUNCTION, 35).
-define(BAD_ARGUMENTS, 36).
-define(UNKNOWN_ELEMENT_IN_AST, 37).
-define(CANNOT_PARSE_DATE, 38).
-define(TOO_LARGE_SIZE_COMPRESSED, 39).
-define(CHECKSUM_DOESNT_MATCH, 40).
-define(CANNOT_PARSE_DATETIME, 41).
-define(NUMBER_OF_ARGUMENTS_DOESNT_MATCH, 42).
-define(ILLEGAL_TYPE_OF_ARGUMENT, 43).
-define(ILLEGAL_COLUMN, 44).
-define(UNKNOWN_FUNCTION, 46).
-define(UNKNOWN_IDENTIFIER, 47).
-define(NOT_IMPLEMENTED, 48).
-define(UNKNOWN_TYPE, 50).

%% Query and table errors
-define(EMPTY_LIST_OF_COLUMNS_QUERIED, 51).
-define(COLUMN_QUERIED_MORE_THAN_ONCE, 52).
-define(TYPE_MISMATCH, 53).
-define(UNKNOWN_STORAGE, 56).
-define(TABLE_ALREADY_EXISTS, 57).
-define(TABLE_METADATA_ALREADY_EXISTS, 58).
-define(ILLEGAL_TYPE_OF_COLUMN_FOR_FILTER, 59).
-define(UNKNOWN_TABLE, 60).
-define(SYNTAX_ERROR, 62).
-define(UNKNOWN_AGGREGATE_FUNCTION, 63).
-define(CANNOT_GET_SIZE_OF_FIELD, 68).
-define(ARGUMENT_OUT_OF_BOUND, 69).
-define(CANNOT_CONVERT_TYPE, 70).
-define(CANNOT_PARSE_NUMBER, 72).
-define(UNKNOWN_FORMAT, 73).

%% File and I/O errors
-define(CANNOT_OPEN_FILE, 76).
-define(CANNOT_CLOSE_FILE, 77).
-define(UNKNOWN_TYPE_OF_QUERY, 78).
-define(INCORRECT_FILE_NAME, 79).
-define(INCORRECT_QUERY, 80).
-define(UNKNOWN_DATABASE, 81).
-define(DATABASE_ALREADY_EXISTS, 82).
-define(DIRECTORY_DOESNT_EXIST, 83).
-define(DIRECTORY_ALREADY_EXISTS, 84).
-define(FORMAT_IS_NOT_SUITABLE_FOR_INPUT, 85).
-define(RECEIVED_ERROR_FROM_REMOTE_IO_SERVER, 86).
-define(CANNOT_SEEK_THROUGH_FILE, 87).
-define(CANNOT_TRUNCATE_FILE, 88).
-define(UNKNOWN_COMPRESSION_METHOD, 89).

%% Network and protocol errors
-define(CANNOT_READ_FROM_SOCKET, 95).
-define(CANNOT_WRITE_TO_SOCKET, 96).
-define(UNKNOWN_PACKET_FROM_CLIENT, 99).
-define(UNKNOWN_PACKET_FROM_SERVER, 100).
-define(UNEXPECTED_PACKET_FROM_CLIENT, 101).
-define(UNEXPECTED_PACKET_FROM_SERVER, 102).
-define(TOO_SMALL_BUFFER_SIZE, 104).
-define(FILE_DOESNT_EXIST, 107).
-define(NO_DATA_TO_INSERT, 108).
-define(THERE_IS_NO_SESSION, 113).
-define(UNKNOWN_SETTING, 115).
-define(THERE_IS_NO_DEFAULT_VALUE, 116).
-define(INCORRECT_DATA, 117).
-define(ENGINE_REQUIRED, 119).

%% Join and aggregation errors
-define(UNSUPPORTED_JOIN_KEYS, 121).
-define(INCOMPATIBLE_COLUMNS, 122).
-define(UNKNOWN_TYPE_OF_AST_NODE, 123).
-define(INCORRECT_ELEMENT_OF_SET, 124).
-define(INCORRECT_RESULT_OF_SCALAR_SUBQUERY, 125).
-define(ILLEGAL_INDEX, 127).
-define(TOO_LARGE_ARRAY_SIZE, 128).
-define(FUNCTION_IS_SPECIAL, 129).
-define(CANNOT_READ_ARRAY_FROM_TEXT, 130).
-define(TOO_LARGE_STRING_SIZE, 131).
-define(AGGREGATE_FUNCTION_DOESNT_ALLOW_PARAMETERS, 133).
-define(PARAMETERS_TO_AGGREGATE_FUNCTIONS_MUST_BE_LITERALS, 134).
-define(ZERO_ARRAY_OR_TUPLE_INDEX, 135).

%% Configuration errors
-define(UNKNOWN_ELEMENT_IN_CONFIG, 137).
-define(EXCESSIVE_ELEMENT_IN_CONFIG, 138).
-define(NO_ELEMENTS_IN_CONFIG, 139).
-define(SAMPLING_NOT_SUPPORTED, 141).
-define(NOT_FOUND_NODE, 142).
-define(UNKNOWN_OVERFLOW_MODE, 145).
-define(UNKNOWN_DIRECTION_OF_SORTING, 152).
-define(ILLEGAL_DIVISION, 153).

%% Resource and performance errors
-define(TOO_MANY_ROWS, 158).
-define(TIMEOUT_EXCEEDED, 159).
-define(TOO_SLOW, 160).
-define(TOO_MANY_COLUMNS, 161).
-define(TOO_DEEP_SUBQUERIES, 162).
-define(READONLY, 164).
-define(TOO_MANY_TEMPORARY_COLUMNS, 165).
-define(TOO_MANY_TEMPORARY_NON_CONST_COLUMNS, 166).
-define(TOO_DEEP_AST, 167).
-define(TOO_BIG_AST, 168).
-define(BAD_TYPE_OF_FIELD, 169).
-define(BAD_GET, 170).
-define(CANNOT_CREATE_DIRECTORY, 172).
-define(CANNOT_ALLOCATE_MEMORY, 173).
-define(CYCLIC_ALIASES, 174).

%% Query processing errors
-define(MULTIPLE_EXPRESSIONS_FOR_ALIAS, 179).
-define(THERE_IS_NO_PROFILE, 180).
-define(ILLEGAL_FINAL, 181).
-define(ILLEGAL_PREWHERE, 182).
-define(UNEXPECTED_EXPRESSION, 183).
-define(ILLEGAL_AGGREGATION, 184).
-define(UNSUPPORTED_COLLATION_LOCALE, 186).
-define(COLLATION_COMPARISON_FAILED, 187).
-define(SIZES_OF_ARRAYS_DONT_MATCH, 190).
-define(SET_SIZE_LIMIT_EXCEEDED, 191).

%% Authentication and access errors
-define(UNKNOWN_USER, 192).
-define(WRONG_PASSWORD, 193).
-define(REQUIRED_PASSWORD, 194).
-define(IP_ADDRESS_NOT_ALLOWED, 195).
-define(UNKNOWN_ADDRESS_PATTERN_TYPE, 196).
-define(DNS_ERROR, 198).
-define(UNKNOWN_QUOTA, 199).
-define(QUOTA_EXCEEDED, 201).
-define(TOO_MANY_SIMULTANEOUS_QUERIES, 202).
-define(NO_FREE_CONNECTION, 203).

%% Network and connection errors
-define(SOCKET_TIMEOUT, 209).
-define(NETWORK_ERROR, 210).
-define(EMPTY_QUERY, 211).
-define(UNKNOWN_LOAD_BALANCING, 212).
-define(UNKNOWN_TOTALS_MODE, 213).
-define(CANNOT_STATVFS, 214).
-define(NOT_AN_AGGREGATE, 215).
-define(QUERY_WITH_SAME_ID_IS_ALREADY_RUNNING, 216).
-define(CLIENT_HAS_CONNECTED_TO_WRONG_PORT, 217).
-define(TABLE_IS_DROPPED, 218).
-define(DATABASE_NOT_EMPTY, 219).

%% Replication errors
-define(NO_ZOOKEEPER, 225).
-define(NO_FILE_IN_DATA_PART, 226).
-define(UNEXPECTED_FILE_IN_DATA_PART, 227).
-define(BAD_SIZE_OF_FILE_IN_DATA_PART, 228).
-define(QUERY_IS_TOO_LARGE, 229).
-define(NOT_FOUND_EXPECTED_DATA_PART, 230).
-define(TOO_MANY_UNEXPECTED_DATA_PARTS, 231).
-define(NO_SUCH_DATA_PART, 232).
-define(BAD_DATA_PART_NAME, 233).
-define(NO_REPLICA_HAS_PART, 234).
-define(DUPLICATE_DATA_PART, 235).
-define(ABORTED, 236).
-define(NO_REPLICA_NAME_GIVEN, 237).
-define(FORMAT_VERSION_TOO_OLD, 238).
-define(CANNOT_MUNMAP, 239).
-define(CANNOT_MREMAP, 240).
-define(MEMORY_LIMIT_EXCEEDED, 241).
-define(TABLE_IS_READ_ONLY, 242).
-define(NOT_ENOUGH_SPACE, 243).
-define(UNEXPECTED_ZOOKEEPER_ERROR, 244).
-define(CORRUPTED_DATA, 246).
-define(INVALID_PARTITION_VALUE, 248).
-define(NO_SUCH_REPLICA, 251).
-define(TOO_MANY_PARTS, 252).
-define(REPLICA_ALREADY_EXISTS, 253).
-define(NO_ACTIVE_REPLICAS, 254).
-define(TOO_MANY_RETRIES_TO_FETCH_PARTS, 255).
-define(PARTITION_ALREADY_EXISTS, 256).
-define(PARTITION_DOESNT_EXIST, 257).
-define(UNION_ALL_RESULT_STRUCTURES_MISMATCH, 258).

%% System and runtime errors
-define(CANNOT_COMPILE_CODE, 263).
-define(INCOMPATIBLE_TYPE_OF_JOIN, 264).
-define(NO_AVAILABLE_REPLICA, 265).
-define(MISMATCH_REPLICAS_DATA_SOURCES, 266).
-define(INFINITE_LOOP, 269).
-define(CANNOT_COMPRESS, 270).
-define(CANNOT_DECOMPRESS, 271).
-define(CANNOT_IO_SUBMIT, 272).
-define(CANNOT_IO_GETEVENTS, 273).
-define(AIO_READ_ERROR, 274).
-define(AIO_WRITE_ERROR, 275).
-define(INDEX_NOT_USED, 277).
-define(ALL_CONNECTION_TRIES_FAILED, 279).
-define(NO_AVAILABLE_DATA, 280).
-define(DICTIONARY_IS_EMPTY, 281).
-define(INCORRECT_INDEX, 282).
-define(UNKNOWN_DISTRIBUTED_PRODUCT_MODE, 283).
-define(WRONG_GLOBAL_SUBQUERY, 284).
-define(TOO_FEW_LIVE_REPLICAS, 285).
-define(UNSATISFIED_QUORUM_FOR_PREVIOUS_WRITE, 286).
-define(UNKNOWN_FORMAT_VERSION, 287).
-define(DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED, 288).
-define(REPLICA_IS_NOT_IN_QUORUM, 289).
-define(LIMIT_EXCEEDED, 290).
-define(DATABASE_ACCESS_DENIED, 291).

%% External system errors
-define(MONGODB_CANNOT_AUTHENTICATE, 293).
-define(CANNOT_WRITE_TO_FILE, 294).
-define(RECEIVED_EMPTY_DATA, 295).
-define(SHARD_HAS_NO_CONNECTIONS, 297).
-define(CANNOT_PIPE, 298).
-define(CANNOT_FORK, 299).
-define(CANNOT_DLSYM, 300).
-define(CANNOT_CREATE_CHILD_PROCESS, 301).
-define(CHILD_WAS_NOT_EXITED_NORMALLY, 302).
-define(CANNOT_SELECT, 303).
-define(CANNOT_WAITPID, 304).
-define(TABLE_WAS_NOT_DROPPED, 305).
-define(TOO_DEEP_RECURSION, 306).
-define(TOO_MANY_BYTES, 307).
-define(UNEXPECTED_NODE_IN_ZOOKEEPER, 308).
-define(FUNCTION_CANNOT_HAVE_PARAMETERS, 309).

%% Configuration and setup errors
-define(INVALID_CONFIG_PARAMETER, 318).
-define(UNKNOWN_STATUS_OF_INSERT, 319).
-define(VALUE_IS_OUT_OF_RANGE_OF_DATA_TYPE, 321).
-define(UNKNOWN_DATABASE_ENGINE, 336).
-define(UNFINISHED, 341).
-define(METADATA_MISMATCH, 342).
-define(SUPPORT_IS_DISABLED, 344).
-define(TABLE_DIFFERS_TOO_MUCH, 345).
-define(CANNOT_CONVERT_CHARSET, 346).
-define(CANNOT_LOAD_CONFIG, 347).
-define(CANNOT_INSERT_NULL_IN_ORDINARY_COLUMN, 349).
-define(AMBIGUOUS_COLUMN_NAME, 352).
-define(INDEX_OF_POSITIONAL_ARGUMENT_IS_OUT_OF_RANGE, 353).
-define(ZLIB_INFLATE_FAILED, 354).
-define(ZLIB_DEFLATE_FAILED, 355).
-define(INTO_OUTFILE_NOT_ALLOWED, 358).
-define(TABLE_SIZE_EXCEEDS_MAX_DROP_SIZE_LIMIT, 359).
-define(CANNOT_CREATE_CHARSET_CONVERTER, 360).
-define(SEEK_POSITION_OUT_OF_BOUND, 361).
-define(CURRENT_WRITE_BUFFER_IS_EXHAUSTED, 362).
-define(CANNOT_CREATE_IO_BUFFER, 363).
-define(RECEIVED_ERROR_TOO_MANY_REQUESTS, 364).
-define(SIZES_OF_NESTED_COLUMNS_ARE_INCONSISTENT, 366).
-define(ALL_REPLICAS_ARE_STALE, 369).
-define(DATA_TYPE_CANNOT_BE_USED_IN_TABLES, 370).
-define(INCONSISTENT_CLUSTER_DEFINITION, 371).

%% Session and security errors
-define(SESSION_NOT_FOUND, 372).
-define(SESSION_IS_LOCKED, 373).
-define(INVALID_SESSION_TIMEOUT, 374).
-define(CANNOT_DLOPEN, 375).
-define(CANNOT_PARSE_UUID, 376).
-define(ILLEGAL_SYNTAX_FOR_DATA_TYPE, 377).
-define(DATA_TYPE_CANNOT_HAVE_ARGUMENTS, 378).
-define(CANNOT_KILL, 380).
-define(HTTP_LENGTH_REQUIRED, 381).
-define(CANNOT_LOAD_CATBOOST_MODEL, 382).
-define(CANNOT_APPLY_CATBOOST_MODEL, 383).
-define(PART_IS_TEMPORARILY_LOCKED, 384).
-define(MULTIPLE_STREAMS_REQUIRED, 385).
-define(NO_COMMON_TYPE, 386).
-define(DICTIONARY_ALREADY_EXISTS, 387).
-define(CANNOT_ASSIGN_OPTIMIZE, 388).
-define(INSERT_WAS_DEDUPLICATED, 389).
-define(CANNOT_GET_CREATE_TABLE_QUERY, 390).
-define(EXTERNAL_LIBRARY_ERROR, 391).
-define(QUERY_IS_PROHIBITED, 392).
-define(THERE_IS_NO_QUERY, 393).
-define(QUERY_WAS_CANCELLED, 394).
-define(FUNCTION_THROW_IF_VALUE_IS_NON_ZERO, 395).
-define(TOO_MANY_ROWS_OR_BYTES, 396).
-define(QUERY_IS_NOT_SUPPORTED_IN_MATERIALIZED_VIEW, 397).
-define(UNKNOWN_MUTATION_COMMAND, 398).
-define(FORMAT_IS_NOT_SUITABLE_FOR_OUTPUT, 399).
-define(CANNOT_STAT, 400).
-define(FEATURE_IS_NOT_ENABLED_AT_BUILD_TIME, 401).
-define(CANNOT_IOSETUP, 402).
-define(INVALID_JOIN_ON_EXPRESSION, 403).
-define(BAD_ODBC_CONNECTION_STRING, 404).
-define(TOP_AND_LIMIT_TOGETHER, 406).
-define(DECIMAL_OVERFLOW, 407).
-define(BAD_REQUEST_PARAMETER, 408).
-define(EXTERNAL_SERVER_IS_NOT_RESPONDING, 410).
-define(PTHREAD_ERROR, 411).
-define(NETLINK_ERROR, 412).
-define(CANNOT_SET_SIGNAL_HANDLER, 413).
-define(ALL_REPLICAS_LOST, 415).
-define(REPLICA_STATUS_CHANGED, 416).
-define(EXPECTED_ALL_OR_ANY, 417).
-define(UNKNOWN_JOIN, 418).
-define(MULTIPLE_ASSIGNMENTS_TO_COLUMN, 419).
-define(CANNOT_UPDATE_COLUMN, 420).
-define(CANNOT_ADD_DIFFERENT_AGGREGATE_STATES, 421).
-define(UNSUPPORTED_URI_SCHEME, 422).
-define(CANNOT_GETTIMEOFDAY, 423).
-define(CANNOT_LINK, 424).
-define(SYSTEM_ERROR, 425).
-define(CANNOT_COMPILE_REGEXP, 427).
-define(FAILED_TO_GETPWUID, 429).
-define(MISMATCHING_USERS_FOR_PROCESS_AND_DATA, 430).
-define(ILLEGAL_SYNTAX_FOR_CODEC_TYPE, 431).
-define(UNKNOWN_CODEC, 432).
-define(ILLEGAL_CODEC_PARAMETER, 433).

%% Protocol and serialization errors
-define(CANNOT_PARSE_PROTOBUF_SCHEMA, 434).
-define(NO_COLUMN_SERIALIZED_TO_REQUIRED_PROTOBUF_FIELD, 435).
-define(PROTOBUF_BAD_CAST, 436).
-define(PROTOBUF_FIELD_NOT_REPEATED, 437).
-define(DATA_TYPE_CANNOT_BE_PROMOTED, 438).
-define(CANNOT_SCHEDULE_TASK, 439).
-define(INVALID_LIMIT_EXPRESSION, 440).
-define(CANNOT_PARSE_DOMAIN_VALUE_FROM_STRING, 441).
-define(BAD_DATABASE_FOR_TEMPORARY_TABLE, 442).
-define(NO_COLUMNS_SERIALIZED_TO_PROTOBUF_FIELDS, 443).
-define(UNKNOWN_PROTOBUF_FORMAT, 444).
-define(CANNOT_MPROTECT, 445).
-define(FUNCTION_NOT_ALLOWED, 446).
-define(HYPERSCAN_CANNOT_SCAN_TEXT, 447).
-define(BROTLI_READ_FAILED, 448).
-define(BROTLI_WRITE_FAILED, 449).
-define(BAD_TTL_EXPRESSION, 450).
-define(BAD_TTL_FILE, 451).
-define(SETTING_CONSTRAINT_VIOLATION, 452).
-define(MYSQL_CLIENT_INSUFFICIENT_CAPABILITIES, 453).
-define(OPENSSL_ERROR, 454).
-define(SUSPICIOUS_TYPE_FOR_LOW_CARDINALITY, 455).
-define(UNKNOWN_QUERY_PARAMETER, 456).
-define(BAD_QUERY_PARAMETER, 457).
-define(CANNOT_UNLINK, 458).
-define(CANNOT_SET_THREAD_PRIORITY, 459).
-define(CANNOT_CREATE_TIMER, 460).
-define(CANNOT_SET_TIMER_PERIOD, 461).
-define(CANNOT_FCNTL, 463).
-define(CANNOT_PARSE_ELF, 464).
-define(CANNOT_PARSE_DWARF, 465).
-define(INSECURE_PATH, 466).
-define(CANNOT_PARSE_BOOL, 467).
-define(CANNOT_PTHREAD_ATTR, 468).
-define(VIOLATED_CONSTRAINT, 469).
-define(INVALID_SETTING_VALUE, 471).
-define(READONLY_SETTING, 472).
-define(DEADLOCK_AVOIDED, 473).
-define(INVALID_TEMPLATE_FORMAT, 474).
-define(INVALID_WITH_FILL_EXPRESSION, 475).
-define(WITH_TIES_WITHOUT_ORDER_BY, 476).
-define(INVALID_USAGE_OF_INPUT, 477).
-define(UNKNOWN_POLICY, 478).
-define(UNKNOWN_DISK, 479).
-define(UNKNOWN_PROTOCOL, 480).
-define(PATH_ACCESS_DENIED, 481).
-define(DICTIONARY_ACCESS_DENIED, 482).
-define(TOO_MANY_REDIRECTS, 483).
-define(INTERNAL_REDIS_ERROR, 484).
-define(CANNOT_GET_CREATE_DICTIONARY_QUERY, 487).
-define(INCORRECT_DICTIONARY_DEFINITION, 489).
-define(CANNOT_FORMAT_DATETIME, 490).
-define(UNACCEPTABLE_URL, 491).
-define(ACCESS_ENTITY_NOT_FOUND, 492).
-define(ACCESS_ENTITY_ALREADY_EXISTS, 493).
-define(ACCESS_STORAGE_READONLY, 495).
-define(QUOTA_REQUIRES_CLIENT_KEY, 496).
-define(ACCESS_DENIED, 497).
-define(LIMIT_BY_WITH_TIES_IS_NOT_SUPPORTED, 498).
-define(S3_ERROR, 499).
-define(AZURE_BLOB_STORAGE_ERROR, 500).
-define(CANNOT_CREATE_DATABASE, 501).
-define(CANNOT_SIGQUEUE, 502).
-define(AGGREGATE_FUNCTION_THROW, 503).
-define(FILE_ALREADY_EXISTS, 504).
-define(UNABLE_TO_SKIP_UNUSED_SHARDS, 507).
-define(UNKNOWN_ACCESS_TYPE, 508).
-define(INVALID_GRANT, 509).
-define(CACHE_DICTIONARY_UPDATE_FAIL, 510).
-define(UNKNOWN_ROLE, 511).
-define(SET_NON_GRANTED_ROLE, 512).
-define(UNKNOWN_PART_TYPE, 513).
-define(ACCESS_STORAGE_FOR_INSERTION_NOT_FOUND, 514).
-define(INCORRECT_ACCESS_ENTITY_DEFINITION, 515).
-define(AUTHENTICATION_FAILED, 516).
-define(CANNOT_ASSIGN_ALTER, 517).
-define(CANNOT_COMMIT_OFFSET, 518).
-define(NO_REMOTE_SHARD_AVAILABLE, 519).
-define(CANNOT_DETACH_DICTIONARY_AS_TABLE, 520).
-define(ATOMIC_RENAME_FAIL, 521).
-define(UNKNOWN_ROW_POLICY, 523).
-define(ALTER_OF_COLUMN_IS_FORBIDDEN, 524).
-define(INCORRECT_DISK_INDEX, 525).
-define(NO_SUITABLE_FUNCTION_IMPLEMENTATION, 527).
-define(CASSANDRA_INTERNAL_ERROR, 528).
-define(NOT_A_LEADER, 529).
-define(CANNOT_CONNECT_RABBITMQ, 530).
-define(CANNOT_FSTAT, 531).
-define(LDAP_ERROR, 532).
-define(UNKNOWN_RAID_TYPE, 535).
-define(CANNOT_RESTORE_FROM_FIELD_DUMP, 536).
-define(ILLEGAL_MYSQL_VARIABLE, 537).
-define(MYSQL_SYNTAX_ERROR, 538).
-define(CANNOT_BIND_RABBITMQ_EXCHANGE, 539).
-define(CANNOT_DECLARE_RABBITMQ_EXCHANGE, 540).
-define(CANNOT_CREATE_RABBITMQ_QUEUE_BINDING, 541).
-define(CANNOT_REMOVE_RABBITMQ_EXCHANGE, 542).
-define(UNKNOWN_MYSQL_DATATYPES_SUPPORT_LEVEL, 543).
-define(ROW_AND_ROWS_TOGETHER, 544).
-define(FIRST_AND_NEXT_TOGETHER, 545).
-define(NO_ROW_DELIMITER, 546).
-define(INVALID_RAID_TYPE, 547).
-define(UNKNOWN_VOLUME, 548).
-define(DATA_TYPE_CANNOT_BE_USED_IN_KEY, 549).
-define(UNRECOGNIZED_ARGUMENTS, 552).
-define(LZMA_STREAM_ENCODER_FAILED, 553).
-define(LZMA_STREAM_DECODER_FAILED, 554).
-define(ROCKSDB_ERROR, 555).
-define(SYNC_MYSQL_USER_ACCESS_ERROR, 556).
-define(UNKNOWN_UNION, 557).
-define(EXPECTED_ALL_OR_DISTINCT, 558).
-define(INVALID_GRPC_QUERY_INFO, 559).
-define(ZSTD_ENCODER_FAILED, 560).
-define(ZSTD_DECODER_FAILED, 561).
-define(TLD_LIST_NOT_FOUND, 562).
-define(CANNOT_READ_MAP_FROM_TEXT, 563).
-define(INTERSERVER_SCHEME_DOESNT_MATCH, 564).
-define(TOO_MANY_PARTITIONS, 565).
-define(CANNOT_RMDIR, 566).
-define(DUPLICATED_PART_UUIDS, 567).
-define(RAFT_ERROR, 568).
-define(MULTIPLE_COLUMNS_SERIALIZED_TO_SAME_PROTOBUF_FIELD, 569).
-define(DATA_TYPE_INCOMPATIBLE_WITH_PROTOBUF_FIELD, 570).
-define(DATABASE_REPLICATION_FAILED, 571).
-define(TOO_MANY_QUERY_PLAN_OPTIMIZATIONS, 572).
-define(EPOLL_ERROR, 573).
-define(DISTRIBUTED_TOO_MANY_PENDING_BYTES, 574).
-define(UNKNOWN_SNAPSHOT, 575).
-define(KERBEROS_ERROR, 576).
-define(INVALID_SHARD_ID, 577).
-define(INVALID_FORMAT_INSERT_QUERY_WITH_DATA, 578).
-define(INCORRECT_PART_TYPE, 579).
-define(CANNOT_SET_ROUNDING_MODE, 580).
-define(TOO_LARGE_DISTRIBUTED_DEPTH, 581).
-define(NO_SUCH_PROJECTION_IN_TABLE, 582).
-define(ILLEGAL_PROJECTION, 583).
-define(PROJECTION_NOT_USED, 584).
-define(CANNOT_PARSE_YAML, 585).
-define(CANNOT_CREATE_FILE, 586).
-define(CONCURRENT_ACCESS_NOT_SUPPORTED, 587).
-define(DISTRIBUTED_BROKEN_BATCH_INFO, 588).
-define(DISTRIBUTED_BROKEN_BATCH_FILES, 589).
-define(CANNOT_SYSCONF, 590).
-define(SQLITE_ENGINE_ERROR, 591).
-define(DATA_ENCRYPTION_ERROR, 592).
-define(ZERO_COPY_REPLICATION_ERROR, 593).
-define(BZIP2_STREAM_DECODER_FAILED, 594).
-define(BZIP2_STREAM_ENCODER_FAILED, 595).
-define(INTERSECT_OR_EXCEPT_RESULT_STRUCTURES_MISMATCH, 596).
-define(NO_SUCH_ERROR_CODE, 597).

%% Backup and restore errors
-define(BACKUP_ALREADY_EXISTS, 598).
-define(BACKUP_NOT_FOUND, 599).
-define(BACKUP_VERSION_NOT_SUPPORTED, 600).
-define(BACKUP_DAMAGED, 601).
-define(NO_BASE_BACKUP, 602).
-define(WRONG_BASE_BACKUP, 603).
-define(BACKUP_ENTRY_ALREADY_EXISTS, 604).
-define(BACKUP_ENTRY_NOT_FOUND, 605).
-define(BACKUP_IS_EMPTY, 606).
-define(CANNOT_RESTORE_DATABASE, 607).
-define(CANNOT_RESTORE_TABLE, 608).
-define(FUNCTION_ALREADY_EXISTS, 609).
-define(CANNOT_DROP_FUNCTION, 610).
-define(CANNOT_CREATE_RECURSIVE_FUNCTION, 611).
-define(POSTGRESQL_CONNECTION_FAILURE, 614).
-define(CANNOT_ADVISE, 615).
-define(UNKNOWN_READ_METHOD, 616).
-define(LZ4_ENCODER_FAILED, 617).
-define(LZ4_DECODER_FAILED, 618).
-define(POSTGRESQL_REPLICATION_INTERNAL_ERROR, 619).
-define(QUERY_NOT_ALLOWED, 620).
-define(CANNOT_NORMALIZE_STRING, 621).
-define(CANNOT_PARSE_CAPN_PROTO_SCHEMA, 622).
-define(CAPN_PROTO_BAD_CAST, 623).
-define(BAD_FILE_TYPE, 624).
-define(IO_SETUP_ERROR, 625).
-define(CANNOT_SKIP_UNKNOWN_FIELD, 626).
-define(BACKUP_ENGINE_NOT_FOUND, 627).
-define(OFFSET_FETCH_WITHOUT_ORDER_BY, 628).
-define(HTTP_RANGE_NOT_SATISFIABLE, 629).
-define(HAVE_DEPENDENT_OBJECTS, 630).
-define(UNKNOWN_FILE_SIZE, 631).
-define(UNEXPECTED_DATA_AFTER_PARSED_VALUE, 632).
-define(QUERY_IS_NOT_SUPPORTED_IN_WINDOW_VIEW, 633).
-define(MONGODB_ERROR, 634).
-define(CANNOT_POLL, 635).
-define(CANNOT_EXTRACT_TABLE_STRUCTURE, 636).
-define(INVALID_TABLE_OVERRIDE, 637).
-define(SNAPPY_UNCOMPRESS_FAILED, 638).
-define(SNAPPY_COMPRESS_FAILED, 639).
-define(NO_HIVEMETASTORE, 640).
-define(CANNOT_APPEND_TO_FILE, 641).
-define(CANNOT_PACK_ARCHIVE, 642).
-define(CANNOT_UNPACK_ARCHIVE, 643).
-define(NUMBER_OF_DIMENSIONS_MISMATCHED, 645).
-define(CANNOT_BACKUP_TABLE, 647).
-define(WRONG_DDL_RENAMING_SETTINGS, 648).
-define(INVALID_TRANSACTION, 649).
-define(SERIALIZATION_ERROR, 650).
-define(CAPN_PROTO_BAD_TYPE, 651).
-define(ONLY_NULLS_WHILE_READING_SCHEMA, 652).
-define(CANNOT_PARSE_BACKUP_SETTINGS, 653).
-define(WRONG_BACKUP_SETTINGS, 654).
-define(FAILED_TO_SYNC_BACKUP_OR_RESTORE, 655).
-define(UNKNOWN_STATUS_OF_TRANSACTION, 659).
-define(HDFS_ERROR, 660).
-define(CANNOT_SEND_SIGNAL, 661).
-define(FS_METADATA_ERROR, 662).
-define(INCONSISTENT_METADATA_FOR_BACKUP, 663).
-define(ACCESS_STORAGE_DOESNT_ALLOW_BACKUP, 664).
-define(CANNOT_CONNECT_NATS, 665).
-define(NOT_INITIALIZED, 667).
-define(INVALID_STATE, 668).
-define(NAMED_COLLECTION_DOESNT_EXIST, 669).
-define(NAMED_COLLECTION_ALREADY_EXISTS, 670).
-define(NAMED_COLLECTION_IS_IMMUTABLE, 671).
-define(INVALID_SCHEDULER_NODE, 672).
-define(RESOURCE_ACCESS_DENIED, 673).
-define(RESOURCE_NOT_FOUND, 674).
-define(CANNOT_PARSE_IPV4, 675).
-define(CANNOT_PARSE_IPV6, 676).
-define(THREAD_WAS_CANCELED, 677).
-define(IO_URING_INIT_FAILED, 678).
-define(IO_URING_SUBMIT_ERROR, 679).
-define(MIXED_ACCESS_PARAMETER_TYPES, 690).
-define(UNKNOWN_ELEMENT_OF_ENUM, 691).
-define(TOO_MANY_MUTATIONS, 692).
-define(AWS_ERROR, 693).
-define(ASYNC_LOAD_CYCLE, 694).
-define(ASYNC_LOAD_FAILED, 695).
-define(ASYNC_LOAD_CANCELED, 696).
-define(CANNOT_RESTORE_TO_NONENCRYPTED_DISK, 697).
-define(INVALID_REDIS_STORAGE_TYPE, 698).
-define(INVALID_REDIS_TABLE_STRUCTURE, 699).
-define(USER_SESSION_LIMIT_EXCEEDED, 700).
-define(CLUSTER_DOESNT_EXIST, 701).
-define(CLIENT_INFO_DOES_NOT_MATCH, 702).
-define(INVALID_IDENTIFIER, 703).
-define(QUERY_CACHE_USED_WITH_NONDETERMINISTIC_FUNCTIONS, 704).
-define(TABLE_NOT_EMPTY, 705).
-define(LIBSSH_ERROR, 706).
-define(GCP_ERROR, 707).
-define(ILLEGAL_STATISTICS, 708).
-define(CANNOT_GET_REPLICATED_DATABASE_SNAPSHOT, 709).
-define(FAULT_INJECTED, 710).
-define(FILECACHE_ACCESS_DENIED, 711).
-define(TOO_MANY_MATERIALIZED_VIEWS, 712).
-define(BROKEN_PROJECTION, 713).
-define(UNEXPECTED_CLUSTER, 714).
-define(CANNOT_DETECT_FORMAT, 715).
-define(CANNOT_FORGET_PARTITION, 716).
-define(EXPERIMENTAL_FEATURE_ERROR, 717).
-define(TOO_SLOW_PARSING, 718).
-define(QUERY_CACHE_USED_WITH_SYSTEM_TABLE, 719).
-define(USER_EXPIRED, 720).
-define(DEPRECATED_FUNCTION, 721).
-define(ASYNC_LOAD_WAIT_FAILED, 722).
-define(PARQUET_EXCEPTION, 723).
-define(TOO_MANY_TABLES, 724).
-define(TOO_MANY_DATABASES, 725).
-define(UNEXPECTED_HTTP_HEADERS, 726).
-define(UNEXPECTED_TABLE_ENGINE, 727).
-define(UNEXPECTED_DATA_TYPE, 728).
-define(ILLEGAL_TIME_SERIES_TAGS, 729).
-define(REFRESH_FAILED, 730).
-define(QUERY_CACHE_USED_WITH_NON_THROW_OVERFLOW_MODE, 731).
-define(TABLE_IS_BEING_RESTARTED, 733).
-define(CANNOT_WRITE_AFTER_BUFFER_CANCELED, 734).
-define(QUERY_WAS_CANCELLED_BY_CLIENT, 735).
-define(DATALAKE_DATABASE_ERROR, 736).
-define(GOOGLE_CLOUD_ERROR, 737).
-define(PART_IS_LOCKED, 738).
-define(BUZZHOUSE, 739).
-define(POTENTIALLY_BROKEN_DATA_PART, 740).
-define(TABLE_UUID_MISMATCH, 741).
-define(DELTA_KERNEL_ERROR, 742).
-define(ICEBERG_SPECIFICATION_VIOLATION, 743).
-define(SESSION_ID_EMPTY, 744).
-define(SERVER_OVERLOADED, 745).
-define(DEPENDENCIES_NOT_FOUND, 746).
-define(FILECACHE_CANNOT_WRITE_THROUGH_CACHE_WITH_CONCURRENT_READS, 747).

%% Distributed cache errors
-define(DISTRIBUTED_CACHE_ERROR, 900).
-define(CANNOT_USE_DISTRIBUTED_CACHE, 901).
-define(PROTOCOL_VERSION_MISMATCH, 902).
-define(LICENSE_EXPIRED, 903).

%% System exceptions
-define(KEEPER_EXCEPTION, 999).
-define(POCO_EXCEPTION, 1000).
-define(STD_EXCEPTION, 1001).
-define(UNKNOWN_EXCEPTION, 1002).
-define(SSH_EXCEPTION, 1003).
-define(STARTUP_SCRIPTS_ERROR, 1004).

%% @doc Get human-readable description for error codes.
%%
%% Maps ClickHouse error codes to descriptive strings.
get_error_code_description(?UNSUPPORTED_METHOD) ->
    {unsupported_method, "Unsupported method"};
get_error_code_description(?UNSUPPORTED_PARAMETER) ->
    {unsupported_parameter, "Unsupported parameter"};
get_error_code_description(?UNEXPECTED_END_OF_FILE) ->
    {unexpected_end_of_file, "Unexpected end of file"};
get_error_code_description(?EXPECTED_END_OF_FILE) ->
    {expected_end_of_file, "Expected end of file"};
get_error_code_description(?CANNOT_PARSE_TEXT) ->
    {cannot_parse_text, "Cannot parse text"};
get_error_code_description(?INCORRECT_NUMBER_OF_COLUMNS) ->
    {incorrect_number_of_columns, "Incorrect number of columns"};
get_error_code_description(?THERE_IS_NO_COLUMN) ->
    {there_is_no_column, "There is no column"};
get_error_code_description(?SIZES_OF_COLUMNS_DOESNT_MATCH) ->
    {sizes_of_columns_doesnt_match, "Sizes of columns doesn't match"};
get_error_code_description(?LOGICAL_ERROR) ->
    {logical_error, "Logical error"};
get_error_code_description(?DUPLICATE_COLUMN) ->
    {duplicate_column, "Duplicate column"};
get_error_code_description(?NO_SUCH_COLUMN_IN_TABLE) ->
    {no_such_column_in_table, "No such column in table"};
get_error_code_description(?SIZE_OF_FIXED_STRING_DOESNT_MATCH) ->
    {size_of_fixed_string_doesnt_match, "Size of fixed string doesn't match"};
get_error_code_description(?NUMBER_OF_COLUMNS_DOESNT_MATCH) ->
    {number_of_columns_doesnt_match, "Number of columns doesn't match"};
get_error_code_description(?CANNOT_READ_FROM_ISTREAM) ->
    {cannot_read_from_istream, "Cannot read from istream"};
get_error_code_description(?CANNOT_WRITE_TO_OSTREAM) ->
    {cannot_write_to_ostream, "Cannot write to ostream"};
get_error_code_description(?CANNOT_PARSE_ESCAPE_SEQUENCE) ->
    {cannot_parse_escape_sequence, "Cannot parse escape sequence"};
get_error_code_description(?CANNOT_PARSE_QUOTED_STRING) ->
    {cannot_parse_quoted_string, "Cannot parse quoted string"};
get_error_code_description(?CANNOT_PARSE_INPUT_ASSERTION_FAILED) ->
    {cannot_parse_input_assertion_failed, "Cannot parse input assertion failed"};
get_error_code_description(?CANNOT_PRINT_FLOAT_OR_DOUBLE_NUMBER) ->
    {cannot_print_float_or_double_number, "Cannot print float or double number"};
get_error_code_description(?ATTEMPT_TO_READ_AFTER_EOF) ->
    {attempt_to_read_after_eof, "Attempt to read after EOF"};
get_error_code_description(?CANNOT_READ_ALL_DATA) ->
    {cannot_read_all_data, "Cannot read all data"};
get_error_code_description(?TOO_MANY_ARGUMENTS_FOR_FUNCTION) ->
    {too_many_arguments_for_function, "Too many arguments for function"};
get_error_code_description(?TOO_FEW_ARGUMENTS_FOR_FUNCTION) ->
    {too_few_arguments_for_function, "Too few arguments for function"};
get_error_code_description(?BAD_ARGUMENTS) ->
    {bad_arguments, "Bad arguments"};
get_error_code_description(?UNKNOWN_ELEMENT_IN_AST) ->
    {unknown_element_in_ast, "Unknown element in AST"};
get_error_code_description(?CANNOT_PARSE_DATE) ->
    {cannot_parse_date, "Cannot parse date"};
get_error_code_description(?TOO_LARGE_SIZE_COMPRESSED) ->
    {too_large_size_compressed, "Too large size compressed"};
get_error_code_description(?CHECKSUM_DOESNT_MATCH) ->
    {checksum_doesnt_match, "Checksum doesn't match"};
get_error_code_description(?CANNOT_PARSE_DATETIME) ->
    {cannot_parse_datetime, "Cannot parse datetime"};
get_error_code_description(?NUMBER_OF_ARGUMENTS_DOESNT_MATCH) ->
    {number_of_arguments_doesnt_match, "Number of arguments doesn't match"};
get_error_code_description(?ILLEGAL_TYPE_OF_ARGUMENT) ->
    {illegal_type_of_argument, "Illegal type of argument"};
get_error_code_description(?ILLEGAL_COLUMN) ->
    {illegal_column, "Illegal column"};
get_error_code_description(?UNKNOWN_FUNCTION) ->
    {unknown_function, "Unknown function"};
get_error_code_description(?UNKNOWN_IDENTIFIER) ->
    {unknown_identifier, "Unknown identifier"};
get_error_code_description(?NOT_IMPLEMENTED) ->
    {not_implemented, "Not implemented"};
get_error_code_description(?UNKNOWN_TYPE) ->
    {unknown_type, "Unknown type"};
get_error_code_description(?EMPTY_LIST_OF_COLUMNS_QUERIED) ->
    {empty_list_of_columns_queried, "Empty list of columns queried"};
get_error_code_description(?COLUMN_QUERIED_MORE_THAN_ONCE) ->
    {column_queried_more_than_once, "Column queried more than once"};
get_error_code_description(?TYPE_MISMATCH) ->
    {type_mismatch, "Type mismatch"};
get_error_code_description(?UNKNOWN_STORAGE) ->
    {unknown_storage, "Unknown storage"};
get_error_code_description(?TABLE_ALREADY_EXISTS) ->
    {table_already_exists, "Table already exists"};
get_error_code_description(?TABLE_METADATA_ALREADY_EXISTS) ->
    {table_metadata_already_exists, "Table metadata already exists"};
get_error_code_description(?ILLEGAL_TYPE_OF_COLUMN_FOR_FILTER) ->
    {illegal_type_of_column_for_filter, "Illegal type of column for filter"};
get_error_code_description(?UNKNOWN_TABLE) ->
    {unknown_table, "Unknown table"};
get_error_code_description(?SYNTAX_ERROR) ->
    {syntax_error, "Syntax error in query"};
get_error_code_description(?UNKNOWN_AGGREGATE_FUNCTION) ->
    {unknown_aggregate_function, "Unknown aggregate function"};
get_error_code_description(?CANNOT_GET_SIZE_OF_FIELD) ->
    {cannot_get_size_of_field, "Cannot get size of field"};
get_error_code_description(?ARGUMENT_OUT_OF_BOUND) ->
    {argument_out_of_bound, "Argument out of bound"};
get_error_code_description(?CANNOT_CONVERT_TYPE) ->
    {cannot_convert_type, "Cannot convert type"};
get_error_code_description(?CANNOT_PARSE_NUMBER) ->
    {cannot_parse_number, "Cannot parse number"};
get_error_code_description(?UNKNOWN_FORMAT) ->
    {unknown_format, "Unknown format"};
get_error_code_description(?CANNOT_OPEN_FILE) ->
    {cannot_open_file, "Cannot open file"};
get_error_code_description(?CANNOT_CLOSE_FILE) ->
    {cannot_close_file, "Cannot close file"};
get_error_code_description(?UNKNOWN_TYPE_OF_QUERY) ->
    {unknown_type_of_query, "Unknown type of query"};
get_error_code_description(?INCORRECT_FILE_NAME) ->
    {incorrect_file_name, "Incorrect file name"};
get_error_code_description(?INCORRECT_QUERY) ->
    {incorrect_query, "Incorrect query"};
get_error_code_description(?UNKNOWN_DATABASE) ->
    {unknown_database, "Unknown database"};
get_error_code_description(?DATABASE_ALREADY_EXISTS) ->
    {database_already_exists, "Database already exists"};
get_error_code_description(?DIRECTORY_DOESNT_EXIST) ->
    {directory_doesnt_exist, "Directory doesn't exist"};
get_error_code_description(?DIRECTORY_ALREADY_EXISTS) ->
    {directory_already_exists, "Directory already exists"};
get_error_code_description(?FORMAT_IS_NOT_SUITABLE_FOR_INPUT) ->
    {format_is_not_suitable_for_input, "Format is not suitable for input"};
get_error_code_description(?RECEIVED_ERROR_FROM_REMOTE_IO_SERVER) ->
    {received_error_from_remote_io_server, "Received error from remote IO server"};
get_error_code_description(?CANNOT_SEEK_THROUGH_FILE) ->
    {cannot_seek_through_file, "Cannot seek through file"};
get_error_code_description(?CANNOT_TRUNCATE_FILE) ->
    {cannot_truncate_file, "Cannot truncate file"};
get_error_code_description(?UNKNOWN_COMPRESSION_METHOD) ->
    {unknown_compression_method, "Unknown compression method"};
get_error_code_description(?CANNOT_READ_FROM_SOCKET) ->
    {cannot_read_from_socket, "Cannot read from socket"};
get_error_code_description(?CANNOT_WRITE_TO_SOCKET) ->
    {cannot_write_to_socket, "Cannot write to socket"};
get_error_code_description(?UNKNOWN_PACKET_FROM_CLIENT) ->
    {unknown_packet_from_client, "Unknown packet from client"};
get_error_code_description(?UNKNOWN_PACKET_FROM_SERVER) ->
    {unknown_packet_from_server, "Unknown packet from server"};
get_error_code_description(?UNEXPECTED_PACKET_FROM_CLIENT) ->
    {unexpected_packet_from_client, "Unexpected packet from client"};
get_error_code_description(?UNEXPECTED_PACKET_FROM_SERVER) ->
    {unexpected_packet_from_server, "Unexpected packet from server"};
get_error_code_description(?TOO_SMALL_BUFFER_SIZE) ->
    {too_small_buffer_size, "Too small buffer size"};
get_error_code_description(?FILE_DOESNT_EXIST) ->
    {file_doesnt_exist, "File doesn't exist"};
get_error_code_description(?NO_DATA_TO_INSERT) ->
    {no_data_to_insert, "No data to insert"};
get_error_code_description(?THERE_IS_NO_SESSION) ->
    {there_is_no_session, "There is no session"};
get_error_code_description(?UNKNOWN_SETTING) ->
    {unknown_setting, "Unknown setting"};
get_error_code_description(?THERE_IS_NO_DEFAULT_VALUE) ->
    {there_is_no_default_value, "There is no default value"};
get_error_code_description(?INCORRECT_DATA) ->
    {incorrect_data, "Incorrect data"};
get_error_code_description(?ENGINE_REQUIRED) ->
    {engine_required, "Engine required"};
get_error_code_description(?UNSUPPORTED_JOIN_KEYS) ->
    {unsupported_join_keys, "Unsupported join keys"};
get_error_code_description(?INCOMPATIBLE_COLUMNS) ->
    {incompatible_columns, "Incompatible columns"};
get_error_code_description(?UNKNOWN_TYPE_OF_AST_NODE) ->
    {unknown_type_of_ast_node, "Unknown type of AST node"};
get_error_code_description(?INCORRECT_ELEMENT_OF_SET) ->
    {incorrect_element_of_set, "Incorrect element of set"};
get_error_code_description(?INCORRECT_RESULT_OF_SCALAR_SUBQUERY) ->
    {incorrect_result_of_scalar_subquery, "Incorrect result of scalar subquery"};
get_error_code_description(?ILLEGAL_INDEX) ->
    {illegal_index, "Illegal index"};
get_error_code_description(?TOO_LARGE_ARRAY_SIZE) ->
    {too_large_array_size, "Too large array size"};
get_error_code_description(?FUNCTION_IS_SPECIAL) ->
    {function_is_special, "Function is special"};
get_error_code_description(?CANNOT_READ_ARRAY_FROM_TEXT) ->
    {cannot_read_array_from_text, "Cannot read array from text"};
get_error_code_description(?TOO_LARGE_STRING_SIZE) ->
    {too_large_string_size, "Too large string size"};
get_error_code_description(?AGGREGATE_FUNCTION_DOESNT_ALLOW_PARAMETERS) ->
    {aggregate_function_doesnt_allow_parameters, "Aggregate function doesn't allow parameters"};
get_error_code_description(?PARAMETERS_TO_AGGREGATE_FUNCTIONS_MUST_BE_LITERALS) ->
    {parameters_to_aggregate_functions_must_be_literals,
        "Parameters to aggregate functions must be literals"};
get_error_code_description(?ZERO_ARRAY_OR_TUPLE_INDEX) ->
    {zero_array_or_tuple_index, "Zero array or tuple index"};
get_error_code_description(?UNKNOWN_ELEMENT_IN_CONFIG) ->
    {unknown_element_in_config, "Unknown element in config"};
get_error_code_description(?EXCESSIVE_ELEMENT_IN_CONFIG) ->
    {excessive_element_in_config, "Excessive element in config"};
get_error_code_description(?NO_ELEMENTS_IN_CONFIG) ->
    {no_elements_in_config, "No elements in config"};
get_error_code_description(?SAMPLING_NOT_SUPPORTED) ->
    {sampling_not_supported, "Sampling not supported"};
get_error_code_description(?NOT_FOUND_NODE) ->
    {not_found_node, "Not found node"};
get_error_code_description(?UNKNOWN_OVERFLOW_MODE) ->
    {unknown_overflow_mode, "Unknown overflow mode"};
get_error_code_description(?UNKNOWN_DIRECTION_OF_SORTING) ->
    {unknown_direction_of_sorting, "Unknown direction of sorting"};
get_error_code_description(?ILLEGAL_DIVISION) ->
    {illegal_division, "Illegal division"};
get_error_code_description(?TOO_MANY_ROWS) ->
    {too_many_rows, "Too many rows"};
get_error_code_description(?TIMEOUT_EXCEEDED) ->
    {timeout_exceeded, "Timeout exceeded"};
get_error_code_description(?TOO_SLOW) ->
    {too_slow, "Too slow"};
get_error_code_description(?TOO_MANY_COLUMNS) ->
    {too_many_columns, "Too many columns"};
get_error_code_description(?TOO_DEEP_SUBQUERIES) ->
    {too_deep_subqueries, "Too deep subqueries"};
get_error_code_description(?READONLY) ->
    {readonly, "Readonly"};
get_error_code_description(?TOO_MANY_TEMPORARY_COLUMNS) ->
    {too_many_temporary_columns, "Too many temporary columns"};
get_error_code_description(?TOO_MANY_TEMPORARY_NON_CONST_COLUMNS) ->
    {too_many_temporary_non_const_columns, "Too many temporary non const columns"};
get_error_code_description(?TOO_DEEP_AST) ->
    {too_deep_ast, "Too deep AST"};
get_error_code_description(?TOO_BIG_AST) ->
    {too_big_ast, "Too big AST"};
get_error_code_description(?BAD_TYPE_OF_FIELD) ->
    {bad_type_of_field, "Bad type of field"};
get_error_code_description(?BAD_GET) ->
    {bad_get, "Bad get"};
get_error_code_description(?CANNOT_CREATE_DIRECTORY) ->
    {cannot_create_directory, "Cannot create directory"};
get_error_code_description(?CANNOT_ALLOCATE_MEMORY) ->
    {cannot_allocate_memory, "Cannot allocate memory"};
get_error_code_description(?CYCLIC_ALIASES) ->
    {cyclic_aliases, "Cyclic aliases"};
get_error_code_description(?MULTIPLE_EXPRESSIONS_FOR_ALIAS) ->
    {multiple_expressions_for_alias, "Multiple expressions for alias"};
get_error_code_description(?THERE_IS_NO_PROFILE) ->
    {there_is_no_profile, "There is no profile"};
get_error_code_description(?ILLEGAL_FINAL) ->
    {illegal_final, "Illegal final"};
get_error_code_description(?ILLEGAL_PREWHERE) ->
    {illegal_prewhere, "Illegal prewhere"};
get_error_code_description(?UNEXPECTED_EXPRESSION) ->
    {unexpected_expression, "Unexpected expression"};
get_error_code_description(?ILLEGAL_AGGREGATION) ->
    {illegal_aggregation, "Illegal aggregation"};
get_error_code_description(?UNSUPPORTED_COLLATION_LOCALE) ->
    {unsupported_collation_locale, "Unsupported collation locale"};
get_error_code_description(?COLLATION_COMPARISON_FAILED) ->
    {collation_comparison_failed, "Collation comparison failed"};
get_error_code_description(?SIZES_OF_ARRAYS_DONT_MATCH) ->
    {sizes_of_arrays_dont_match, "Sizes of arrays don't match"};
get_error_code_description(?SET_SIZE_LIMIT_EXCEEDED) ->
    {set_size_limit_exceeded, "Set size limit exceeded"};
get_error_code_description(?UNKNOWN_USER) ->
    {unknown_user, "Unknown user"};
get_error_code_description(?WRONG_PASSWORD) ->
    {wrong_password, "Wrong password"};
get_error_code_description(?REQUIRED_PASSWORD) ->
    {required_password, "Required password"};
get_error_code_description(?IP_ADDRESS_NOT_ALLOWED) ->
    {ip_address_not_allowed, "IP address not allowed"};
get_error_code_description(?UNKNOWN_ADDRESS_PATTERN_TYPE) ->
    {unknown_address_pattern_type, "Unknown address pattern type"};
get_error_code_description(?DNS_ERROR) ->
    {dns_error, "DNS error"};
get_error_code_description(?UNKNOWN_QUOTA) ->
    {unknown_quota, "Unknown quota"};
get_error_code_description(?QUOTA_EXCEEDED) ->
    {quota_exceeded, "Quota exceeded"};
get_error_code_description(?TOO_MANY_SIMULTANEOUS_QUERIES) ->
    {too_many_simultaneous_queries, "Too many simultaneous queries"};
get_error_code_description(?NO_FREE_CONNECTION) ->
    {no_free_connection, "No free connection"};
get_error_code_description(?SOCKET_TIMEOUT) ->
    {socket_timeout, "Socket timeout"};
get_error_code_description(?NETWORK_ERROR) ->
    {network_error, "Network error"};
get_error_code_description(?EMPTY_QUERY) ->
    {empty_query, "Empty query"};
get_error_code_description(?UNKNOWN_LOAD_BALANCING) ->
    {unknown_load_balancing, "Unknown load balancing"};
get_error_code_description(?UNKNOWN_TOTALS_MODE) ->
    {unknown_totals_mode, "Unknown totals mode"};
get_error_code_description(?CANNOT_STATVFS) ->
    {cannot_statvfs, "Cannot statvfs"};
get_error_code_description(?NOT_AN_AGGREGATE) ->
    {not_an_aggregate, "Not an aggregate"};
get_error_code_description(?QUERY_WITH_SAME_ID_IS_ALREADY_RUNNING) ->
    {query_with_same_id_is_already_running, "Query with same ID is already running"};
get_error_code_description(?CLIENT_HAS_CONNECTED_TO_WRONG_PORT) ->
    {client_has_connected_to_wrong_port, "Client has connected to wrong port"};
get_error_code_description(?TABLE_IS_DROPPED) ->
    {table_is_dropped, "Table is dropped"};
get_error_code_description(?DATABASE_NOT_EMPTY) ->
    {database_not_empty, "Database not empty"};
get_error_code_description(?NO_ZOOKEEPER) ->
    {no_zookeeper, "No zookeeper"};
get_error_code_description(?NO_FILE_IN_DATA_PART) ->
    {no_file_in_data_part, "No file in data part"};
get_error_code_description(?UNEXPECTED_FILE_IN_DATA_PART) ->
    {unexpected_file_in_data_part, "Unexpected file in data part"};
get_error_code_description(?BAD_SIZE_OF_FILE_IN_DATA_PART) ->
    {bad_size_of_file_in_data_part, "Bad size of file in data part"};
get_error_code_description(?QUERY_IS_TOO_LARGE) ->
    {query_is_too_large, "Query is too large"};
get_error_code_description(?NOT_FOUND_EXPECTED_DATA_PART) ->
    {not_found_expected_data_part, "Not found expected data part"};
get_error_code_description(?TOO_MANY_UNEXPECTED_DATA_PARTS) ->
    {too_many_unexpected_data_parts, "Too many unexpected data parts"};
get_error_code_description(?NO_SUCH_DATA_PART) ->
    {no_such_data_part, "No such data part"};
get_error_code_description(?BAD_DATA_PART_NAME) ->
    {bad_data_part_name, "Bad data part name"};
get_error_code_description(?NO_REPLICA_HAS_PART) ->
    {no_replica_has_part, "No replica has part"};
get_error_code_description(?DUPLICATE_DATA_PART) ->
    {duplicate_data_part, "Duplicate data part"};
get_error_code_description(?ABORTED) ->
    {aborted, "Aborted"};
get_error_code_description(?NO_REPLICA_NAME_GIVEN) ->
    {no_replica_name_given, "No replica name given"};
get_error_code_description(?FORMAT_VERSION_TOO_OLD) ->
    {format_version_too_old, "Format version too old"};
get_error_code_description(?CANNOT_MUNMAP) ->
    {cannot_munmap, "Cannot munmap"};
get_error_code_description(?CANNOT_MREMAP) ->
    {cannot_mremap, "Cannot mremap"};
get_error_code_description(?MEMORY_LIMIT_EXCEEDED) ->
    {memory_limit_exceeded, "Memory limit exceeded"};
get_error_code_description(?TABLE_IS_READ_ONLY) ->
    {table_is_read_only, "Table is read only"};
get_error_code_description(?NOT_ENOUGH_SPACE) ->
    {not_enough_space, "Not enough space"};
get_error_code_description(?UNEXPECTED_ZOOKEEPER_ERROR) ->
    {unexpected_zookeeper_error, "Unexpected zookeeper error"};
get_error_code_description(?CORRUPTED_DATA) ->
    {corrupted_data, "Corrupted data"};
get_error_code_description(?INVALID_PARTITION_VALUE) ->
    {invalid_partition_value, "Invalid partition value"};
get_error_code_description(?NO_SUCH_REPLICA) ->
    {no_such_replica, "No such replica"};
get_error_code_description(?TOO_MANY_PARTS) ->
    {too_many_parts, "Too many parts"};
get_error_code_description(?REPLICA_ALREADY_EXISTS) ->
    {replica_already_exists, "Replica already exists"};
get_error_code_description(?NO_ACTIVE_REPLICAS) ->
    {no_active_replicas, "No active replicas"};
get_error_code_description(?TOO_MANY_RETRIES_TO_FETCH_PARTS) ->
    {too_many_retries_to_fetch_parts, "Too many retries to fetch parts"};
get_error_code_description(?PARTITION_ALREADY_EXISTS) ->
    {partition_already_exists, "Partition already exists"};
get_error_code_description(?PARTITION_DOESNT_EXIST) ->
    {partition_doesnt_exist, "Partition doesn't exist"};
get_error_code_description(?UNION_ALL_RESULT_STRUCTURES_MISMATCH) ->
    {union_all_result_structures_mismatch, "Union all result structures mismatch"};
get_error_code_description(?CANNOT_COMPILE_CODE) ->
    {cannot_compile_code, "Cannot compile code"};
get_error_code_description(?INCOMPATIBLE_TYPE_OF_JOIN) ->
    {incompatible_type_of_join, "Incompatible type of join"};
get_error_code_description(?NO_AVAILABLE_REPLICA) ->
    {no_available_replica, "No available replica"};
get_error_code_description(?MISMATCH_REPLICAS_DATA_SOURCES) ->
    {mismatch_replicas_data_sources, "Mismatch replicas data sources"};
get_error_code_description(?INFINITE_LOOP) ->
    {infinite_loop, "Infinite loop"};
get_error_code_description(?CANNOT_COMPRESS) ->
    {cannot_compress, "Cannot compress"};
get_error_code_description(?CANNOT_DECOMPRESS) ->
    {cannot_decompress, "Cannot decompress"};
get_error_code_description(?CANNOT_IO_SUBMIT) ->
    {cannot_io_submit, "Cannot IO submit"};
get_error_code_description(?CANNOT_IO_GETEVENTS) ->
    {cannot_io_getevents, "Cannot IO getevents"};
get_error_code_description(?AIO_READ_ERROR) ->
    {aio_read_error, "AIO read error"};
get_error_code_description(?AIO_WRITE_ERROR) ->
    {aio_write_error, "AIO write error"};
get_error_code_description(?INDEX_NOT_USED) ->
    {index_not_used, "Index not used"};
get_error_code_description(?ALL_CONNECTION_TRIES_FAILED) ->
    {all_connection_tries_failed, "All connection tries failed"};
get_error_code_description(?NO_AVAILABLE_DATA) ->
    {no_available_data, "No available data"};
get_error_code_description(?DICTIONARY_IS_EMPTY) ->
    {dictionary_is_empty, "Dictionary is empty"};
get_error_code_description(?INCORRECT_INDEX) ->
    {incorrect_index, "Incorrect index"};
get_error_code_description(?UNKNOWN_DISTRIBUTED_PRODUCT_MODE) ->
    {unknown_distributed_product_mode, "Unknown distributed product mode"};
get_error_code_description(?WRONG_GLOBAL_SUBQUERY) ->
    {wrong_global_subquery, "Wrong global subquery"};
get_error_code_description(?TOO_FEW_LIVE_REPLICAS) ->
    {too_few_live_replicas, "Too few live replicas"};
get_error_code_description(?UNSATISFIED_QUORUM_FOR_PREVIOUS_WRITE) ->
    {unsatisfied_quorum_for_previous_write, "Unsatisfied quorum for previous write"};
get_error_code_description(?UNKNOWN_FORMAT_VERSION) ->
    {unknown_format_version, "Unknown format version"};
get_error_code_description(?DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED) ->
    {distributed_in_join_subquery_denied, "Distributed in join subquery denied"};
get_error_code_description(?REPLICA_IS_NOT_IN_QUORUM) ->
    {replica_is_not_in_quorum, "Replica is not in quorum"};
get_error_code_description(?LIMIT_EXCEEDED) ->
    {limit_exceeded, "Limit exceeded"};
get_error_code_description(?DATABASE_ACCESS_DENIED) ->
    {database_access_denied, "Database access denied"};
get_error_code_description(?MONGODB_CANNOT_AUTHENTICATE) ->
    {mongodb_cannot_authenticate, "MongoDB cannot authenticate"};
get_error_code_description(?CANNOT_WRITE_TO_FILE) ->
    {cannot_write_to_file, "Cannot write to file"};
get_error_code_description(?RECEIVED_EMPTY_DATA) ->
    {received_empty_data, "Received empty data"};
get_error_code_description(?SHARD_HAS_NO_CONNECTIONS) ->
    {shard_has_no_connections, "Shard has no connections"};
get_error_code_description(?CANNOT_PIPE) ->
    {cannot_pipe, "Cannot pipe"};
get_error_code_description(?CANNOT_FORK) ->
    {cannot_fork, "Cannot fork"};
get_error_code_description(?CANNOT_DLSYM) ->
    {cannot_dlsym, "Cannot dlsym"};
get_error_code_description(?CANNOT_CREATE_CHILD_PROCESS) ->
    {cannot_create_child_process, "Cannot create child process"};
get_error_code_description(?CHILD_WAS_NOT_EXITED_NORMALLY) ->
    {child_was_not_exited_normally, "Child was not exited normally"};
get_error_code_description(?CANNOT_SELECT) ->
    {cannot_select, "Cannot select"};
get_error_code_description(?CANNOT_WAITPID) ->
    {cannot_waitpid, "Cannot waitpid"};
get_error_code_description(?TABLE_WAS_NOT_DROPPED) ->
    {table_was_not_dropped, "Table was not dropped"};
get_error_code_description(?TOO_DEEP_RECURSION) ->
    {too_deep_recursion, "Too deep recursion"};
get_error_code_description(?TOO_MANY_BYTES) ->
    {too_many_bytes, "Too many bytes"};
get_error_code_description(?UNEXPECTED_NODE_IN_ZOOKEEPER) ->
    {unexpected_node_in_zookeeper, "Unexpected node in zookeeper"};
get_error_code_description(?FUNCTION_CANNOT_HAVE_PARAMETERS) ->
    {function_cannot_have_parameters, "Function cannot have parameters"};
get_error_code_description(?INVALID_CONFIG_PARAMETER) ->
    {invalid_config_parameter, "Invalid config parameter"};
get_error_code_description(?UNKNOWN_STATUS_OF_INSERT) ->
    {unknown_status_of_insert, "Unknown status of insert"};
get_error_code_description(?VALUE_IS_OUT_OF_RANGE_OF_DATA_TYPE) ->
    {value_is_out_of_range_of_data_type, "Value is out of range of data type"};
get_error_code_description(?UNKNOWN_DATABASE_ENGINE) ->
    {unknown_database_engine, "Unknown database engine"};
get_error_code_description(?UNFINISHED) ->
    {unfinished, "Unfinished"};
get_error_code_description(?METADATA_MISMATCH) ->
    {metadata_mismatch, "Metadata mismatch"};
get_error_code_description(?SUPPORT_IS_DISABLED) ->
    {support_is_disabled, "Support is disabled"};
get_error_code_description(?TABLE_DIFFERS_TOO_MUCH) ->
    {table_differs_too_much, "Table differs too much"};
get_error_code_description(?CANNOT_CONVERT_CHARSET) ->
    {cannot_convert_charset, "Cannot convert charset"};
get_error_code_description(?CANNOT_LOAD_CONFIG) ->
    {cannot_load_config, "Cannot load config"};
get_error_code_description(?CANNOT_INSERT_NULL_IN_ORDINARY_COLUMN) ->
    {cannot_insert_null_in_ordinary_column, "Cannot insert null in ordinary column"};
get_error_code_description(?AMBIGUOUS_COLUMN_NAME) ->
    {ambiguous_column_name, "Ambiguous column name"};
get_error_code_description(?INDEX_OF_POSITIONAL_ARGUMENT_IS_OUT_OF_RANGE) ->
    {index_of_positional_argument_is_out_of_range, "Index of positional argument is out of range"};
get_error_code_description(?ZLIB_INFLATE_FAILED) ->
    {zlib_inflate_failed, "Zlib inflate failed"};
get_error_code_description(?ZLIB_DEFLATE_FAILED) ->
    {zlib_deflate_failed, "Zlib deflate failed"};
get_error_code_description(?INTO_OUTFILE_NOT_ALLOWED) ->
    {into_outfile_not_allowed, "Into outfile not allowed"};
get_error_code_description(?TABLE_SIZE_EXCEEDS_MAX_DROP_SIZE_LIMIT) ->
    {table_size_exceeds_max_drop_size_limit, "Table size exceeds max drop size limit"};
get_error_code_description(?CANNOT_CREATE_CHARSET_CONVERTER) ->
    {cannot_create_charset_converter, "Cannot create charset converter"};
get_error_code_description(?SEEK_POSITION_OUT_OF_BOUND) ->
    {seek_position_out_of_bound, "Seek position out of bound"};
get_error_code_description(?CURRENT_WRITE_BUFFER_IS_EXHAUSTED) ->
    {current_write_buffer_is_exhausted, "Current write buffer is exhausted"};
get_error_code_description(?CANNOT_CREATE_IO_BUFFER) ->
    {cannot_create_io_buffer, "Cannot create IO buffer"};
get_error_code_description(?RECEIVED_ERROR_TOO_MANY_REQUESTS) ->
    {received_error_too_many_requests, "Received error too many requests"};
get_error_code_description(?SIZES_OF_NESTED_COLUMNS_ARE_INCONSISTENT) ->
    {sizes_of_nested_columns_are_inconsistent, "Sizes of nested columns are inconsistent"};
get_error_code_description(?ALL_REPLICAS_ARE_STALE) ->
    {all_replicas_are_stale, "All replicas are stale"};
get_error_code_description(?DATA_TYPE_CANNOT_BE_USED_IN_TABLES) ->
    {data_type_cannot_be_used_in_tables, "Data type cannot be used in tables"};
get_error_code_description(?INCONSISTENT_CLUSTER_DEFINITION) ->
    {inconsistent_cluster_definition, "Inconsistent cluster definition"};
get_error_code_description(?SESSION_NOT_FOUND) ->
    {session_not_found, "Session not found"};
get_error_code_description(?SESSION_IS_LOCKED) ->
    {session_is_locked, "Session is locked"};
get_error_code_description(?INVALID_SESSION_TIMEOUT) ->
    {invalid_session_timeout, "Invalid session timeout"};
get_error_code_description(?CANNOT_DLOPEN) ->
    {cannot_dlopen, "Cannot dlopen"};
get_error_code_description(?CANNOT_PARSE_UUID) ->
    {cannot_parse_uuid, "Cannot parse UUID"};
get_error_code_description(?ILLEGAL_SYNTAX_FOR_DATA_TYPE) ->
    {illegal_syntax_for_data_type, "Illegal syntax for data type"};
get_error_code_description(?DATA_TYPE_CANNOT_HAVE_ARGUMENTS) ->
    {data_type_cannot_have_arguments, "Data type cannot have arguments"};
get_error_code_description(?CANNOT_KILL) ->
    {cannot_kill, "Cannot kill"};
get_error_code_description(?HTTP_LENGTH_REQUIRED) ->
    {http_length_required, "HTTP length required"};
get_error_code_description(?CANNOT_LOAD_CATBOOST_MODEL) ->
    {cannot_load_catboost_model, "Cannot load catboost model"};
get_error_code_description(?CANNOT_APPLY_CATBOOST_MODEL) ->
    {cannot_apply_catboost_model, "Cannot apply catboost model"};
get_error_code_description(?PART_IS_TEMPORARILY_LOCKED) ->
    {part_is_temporarily_locked, "Part is temporarily locked"};
get_error_code_description(?MULTIPLE_STREAMS_REQUIRED) ->
    {multiple_streams_required, "Multiple streams required"};
get_error_code_description(?NO_COMMON_TYPE) ->
    {no_common_type, "No common type"};
get_error_code_description(?DICTIONARY_ALREADY_EXISTS) ->
    {dictionary_already_exists, "Dictionary already exists"};
get_error_code_description(?CANNOT_ASSIGN_OPTIMIZE) ->
    {cannot_assign_optimize, "Cannot assign optimize"};
get_error_code_description(?INSERT_WAS_DEDUPLICATED) ->
    {insert_was_deduplicated, "Insert was deduplicated"};
get_error_code_description(?CANNOT_GET_CREATE_TABLE_QUERY) ->
    {cannot_get_create_table_query, "Cannot get create table query"};
get_error_code_description(?EXTERNAL_LIBRARY_ERROR) ->
    {external_library_error, "External library error"};
get_error_code_description(?QUERY_IS_PROHIBITED) ->
    {query_is_prohibited, "Query is prohibited"};
get_error_code_description(?THERE_IS_NO_QUERY) ->
    {there_is_no_query, "There is no query"};
get_error_code_description(?QUERY_WAS_CANCELLED) ->
    {query_was_cancelled, "Query was cancelled"};
get_error_code_description(?FUNCTION_THROW_IF_VALUE_IS_NON_ZERO) ->
    {function_throw_if_value_is_non_zero, "Function throw if value is non zero"};
get_error_code_description(?TOO_MANY_ROWS_OR_BYTES) ->
    {too_many_rows_or_bytes, "Too many rows or bytes"};
get_error_code_description(?QUERY_IS_NOT_SUPPORTED_IN_MATERIALIZED_VIEW) ->
    {query_is_not_supported_in_materialized_view, "Query is not supported in materialized view"};
get_error_code_description(?UNKNOWN_MUTATION_COMMAND) ->
    {unknown_mutation_command, "Unknown mutation command"};
get_error_code_description(?FORMAT_IS_NOT_SUITABLE_FOR_OUTPUT) ->
    {format_is_not_suitable_for_output, "Format is not suitable for output"};
get_error_code_description(?CANNOT_STAT) ->
    {cannot_stat, "Cannot stat"};
get_error_code_description(?FEATURE_IS_NOT_ENABLED_AT_BUILD_TIME) ->
    {feature_is_not_enabled_at_build_time, "Feature is not enabled at build time"};
get_error_code_description(?CANNOT_IOSETUP) ->
    {cannot_iosetup, "Cannot iosetup"};
get_error_code_description(?INVALID_JOIN_ON_EXPRESSION) ->
    {invalid_join_on_expression, "Invalid join on expression"};
get_error_code_description(?BAD_ODBC_CONNECTION_STRING) ->
    {bad_odbc_connection_string, "Bad ODBC connection string"};
get_error_code_description(?TOP_AND_LIMIT_TOGETHER) ->
    {top_and_limit_together, "Top and limit together"};
get_error_code_description(?DECIMAL_OVERFLOW) ->
    {decimal_overflow, "Decimal overflow"};
get_error_code_description(?BAD_REQUEST_PARAMETER) ->
    {bad_request_parameter, "Bad request parameter"};
get_error_code_description(?EXTERNAL_SERVER_IS_NOT_RESPONDING) ->
    {external_server_is_not_responding, "External server is not responding"};
get_error_code_description(?PTHREAD_ERROR) ->
    {pthread_error, "Pthread error"};
get_error_code_description(?NETLINK_ERROR) ->
    {netlink_error, "Netlink error"};
get_error_code_description(?CANNOT_SET_SIGNAL_HANDLER) ->
    {cannot_set_signal_handler, "Cannot set signal handler"};
get_error_code_description(?ALL_REPLICAS_LOST) ->
    {all_replicas_lost, "All replicas lost"};
get_error_code_description(?REPLICA_STATUS_CHANGED) ->
    {replica_status_changed, "Replica status changed"};
get_error_code_description(?EXPECTED_ALL_OR_ANY) ->
    {expected_all_or_any, "Expected all or any"};
get_error_code_description(?UNKNOWN_JOIN) ->
    {unknown_join, "Unknown join"};
get_error_code_description(?MULTIPLE_ASSIGNMENTS_TO_COLUMN) ->
    {multiple_assignments_to_column, "Multiple assignments to column"};
get_error_code_description(?CANNOT_UPDATE_COLUMN) ->
    {cannot_update_column, "Cannot update column"};
get_error_code_description(?CANNOT_ADD_DIFFERENT_AGGREGATE_STATES) ->
    {cannot_add_different_aggregate_states, "Cannot add different aggregate states"};
get_error_code_description(?UNSUPPORTED_URI_SCHEME) ->
    {unsupported_uri_scheme, "Unsupported URI scheme"};
get_error_code_description(?CANNOT_GETTIMEOFDAY) ->
    {cannot_gettimeofday, "Cannot gettimeofday"};
get_error_code_description(?CANNOT_LINK) ->
    {cannot_link, "Cannot link"};
get_error_code_description(?SYSTEM_ERROR) ->
    {system_error, "System error"};
get_error_code_description(?CANNOT_COMPILE_REGEXP) ->
    {cannot_compile_regexp, "Cannot compile regexp"};
get_error_code_description(?FAILED_TO_GETPWUID) ->
    {failed_to_getpwuid, "Failed to getpwuid"};
get_error_code_description(?MISMATCHING_USERS_FOR_PROCESS_AND_DATA) ->
    {mismatching_users_for_process_and_data, "Mismatching users for process and data"};
get_error_code_description(?ILLEGAL_SYNTAX_FOR_CODEC_TYPE) ->
    {illegal_syntax_for_codec_type, "Illegal syntax for codec type"};
get_error_code_description(?UNKNOWN_CODEC) ->
    {unknown_codec, "Unknown codec"};
get_error_code_description(?ILLEGAL_CODEC_PARAMETER) ->
    {illegal_codec_parameter, "Illegal codec parameter"};
get_error_code_description(?AUTHENTICATION_FAILED) ->
    {authentication_failed,
        "Authentication failed: password is incorrect or there is no user with such name"};
get_error_code_description(?ACCESS_DENIED) ->
    {access_denied, "Access denied"};
get_error_code_description(?S3_ERROR) ->
    {s3_error, "S3 error"};
get_error_code_description(?AZURE_BLOB_STORAGE_ERROR) ->
    {azure_blob_storage_error, "Azure blob storage error"};
get_error_code_description(?KEEPER_EXCEPTION) ->
    {keeper_exception, "Keeper exception"};
get_error_code_description(?POCO_EXCEPTION) ->
    {poco_exception, "Poco exception"};
get_error_code_description(?STD_EXCEPTION) ->
    {std_exception, "Standard exception"};
get_error_code_description(?UNKNOWN_EXCEPTION) ->
    {unknown_exception, "Unknown exception"};
get_error_code_description(?SSH_EXCEPTION) ->
    {ssh_exception, "SSH exception"};
get_error_code_description(?STARTUP_SCRIPTS_ERROR) ->
    {startup_scripts_error, "Startup scripts error"};
get_error_code_description(_) ->
    {unknown_error_code, "Unknown error code"}.

get_error(Code) ->
    {Error, _} = get_error_code_description(Code),
    Error.

get_readable_error(Code) ->
    {_, Readable} = get_error_code_description(Code),
    Readable.
