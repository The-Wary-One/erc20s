object "ERC20" {
    code {
        // Constructor args are appended to the contract's code
        // example: name = "Token", symbol = "TK"
        // name offset => nbArgs * 0x20 bytes because it's the first dynamic length argument
        // 0000000000000000000000000000000000000000000000000000000000000040
        // symbol offset => (nbArgs + (name.len / 0x20) + 0x1 + 0x1) * 0x20
        // 0000000000000000000000000000000000000000000000000000000000000080
        // name len
        // 0000000000000000000000000000000000000000000000000000000000000005
        // name data
        // 546f6b656e000000000000000000000000000000000000000000000000000000
        // symbol len
        // 0000000000000000000000000000000000000000000000000000000000000002
        // symbol data
        // 544b000000000000000000000000000000000000000000000000000000000000

        // Get the creation code size
        let contractSize := datasize("ERC20")
        // Calculate the constructor arguments size
        let argsSize := sub(codesize(), contractSize)
        // Copy encoded args to memory
        codecopy(0x00, contractSize, argsSize)
        // Store name arg to slot 0
        memStringArgToSlot(0x00)
        // Store symbol arg to slot 1
        memStringArgToSlot(0x01)
        // Store caller to slot 2
        sstore(0x02, caller())

        // Return the runtime bytecode
        datacopy(0x00, dataoffset("runtime"), datasize("runtime"))
        return(0x00, datasize("runtime"))

        /* --- storage layout --- */

        // function nameSlot() -> slot { slot := 0 }
        // function symbolSlot() -> slot { slot := 1 }
        // function ownerSlot() -> slot { slot := 2 }

        /* --- storage helpers --- */

        function memStringArgToSlot(argIndex) {
            // Get the string len offset
            let offset := mload(mul(argIndex, 0x20))
            // Load the arg len
            let len := mload(offset)
            // If len < 32, we can store the entire string and its len in the slot
            if lt(len, 0x20) {
                // Load the string data onto the stack
                let data := mload(add(offset, 0x20))
                // Add to it (i.e. append) the len * 2 (i.e. shl 1)
                let compactString := add(data, shl(0x01, len))
                // Store it to its slot
                sstore(argIndex, compactString)
                // Exit function
                leave
            }
            // Else
            // Store len * 2 + 1 at slot and string data at keccak256(slot)
            let slotData := add(shl(0x01, len), 0x01)
            sstore(argIndex, slotData)
            // Store string data starting keccak256(slot)
            mstore(0x00, argIndex)
            let startingDataSlot := keccak256(0x00, 0x20)
            // How many words are needed to store the string ? len / 32 + 1
            let neededWords := add(div(len, 0x20), 0x01)
            // Store all data words starting at the keccak256(slot)
            let stopAt := add(neededWords, 0x01)
            let offsetWithoutLen := add(offset, 0x20)
            for { let i := 0x00 } lt(i, stopAt) { i := add(i, 0x01) } {
                // Load the string data word onto the stack
                let data := mload(add(offsetWithoutLen, mul(i, 0x20)))
                sstore(add(startingDataSlot, i), data)
            }
        }
    }

    object "runtime" {
        code {
            //// Update the Solidity free memory pointer
            //function allocate(size) -> memPtr {
            //    // Load the free memory pointer value
            //    memPtr := mload(0x40)
            //    // Initialize it to 0x80
            //    if iszero(memPtr) { memPtr := 0x80 }
            //    // Update the free memory pointer value
            //    mstore(0x40, add(memPtr, size))
            //}

            // Extract the called function by getting the first 4 bytes of calldata
            let selector := shr(0xe0, calldataload(0x00))
            // Dispatcher
            switch selector
            case 0x06fdde03 /* "name()" */ {
                returnStorageString(nameSlot())
            }
            case 0x95d89b41 /* "symbol()" */ {
                returnStorageString(symbolSlot())
            }
            case 0x8da5cb5b /* "owner()" */ {
                returnAddress(owner())
            }
            default {
                revert(0x00, 0x00)
            }

            /* --- calldata decoding functions --- */

            /* --- calldata encoding functions --- */

            function returnUint(u) {
                mstore(0x00, u)
                return(0x00, 0x20)
            }

            function returnAddress(addr) {
                returnUint(addr)
            }

            function returnStorageString(slot) {
                // Abi encoded string memory layout
                // example: "Token"
                // offset => nbArgs * 0x20 bytes because it's the first dynamic length argument
                // 0x00 => 0x0000000000000000000000000000000000000000000000000000000000000020
                // length
                // 0x20 => 0x0000000000000000000000000000000000000000000000000000000000000005
                // string data
                // 0x40 => 0x546f6b656e000000000000000000000000000000000000000000000000000000

                let startingMemPtr
                // Store offset
                mstore(startingMemPtr, 0x20)
                // Load the data in at slot
                let slotData := sload(slot)
                // Check if the string data is stored in the slot by checking if the last bit is 0
                switch mod(slotData, 0x02)
                case 1 /* Not Packed */ {
                    // Store length = slot data / 2 - 1 (i.e. shr 1)
                    let len := shr(0x01, slotData)
                    mstore(add(startingMemPtr, 0x20), len)
                    // Load string data starting keccak256(slot)
                    let dataMemPtr := add(startingMemPtr, 0x40)
                    mstore(dataMemPtr, slot)
                    let startingDataSlot := keccak256(dataMemPtr, 0x20)
                    // How many words are needed to store the string ? len / 32 + 1
                    let neededWords := add(div(len, 0x20), 0x01)
                    // Load all data words starting at the keccak256(slot)
                    for { let i := 0x00 } lt(i, neededWords) { i := add(i, 0x01) } {
                        // Load the string data word onto memory
                        let data := sload(add(startingDataSlot, i))
                        mstore(add(dataMemPtr, mul(i, 0x20)), data)
                    }
                    // return the starting memory pointer and size
                    return(0x00, add(0x40, mul(neededWords, 0x20)))
                }
                default /* Packed */ {
                    // Store length = last slot data byte / 2 (i.e. shr 1); (max = 31)
                    mstore(add(startingMemPtr, 0x20), shr(0x01, byte(0x1f, slotData)))
                    // Store data
                    mstore(add(startingMemPtr, 0x40), slotData)
                    // Clean the last byte (length)
                    mstore8(add(startingMemPtr, 0x5f), 0x00)
                    // return the starting memory pointer and size
                    return(0x00, 0x60)
                }
            }

            /* --- storage layout --- */

            function nameSlot() -> slot { slot := 0 }
            function symbolSlot() -> slot { slot := 1 }
            function ownerSlot() -> slot { slot := 2 }

            /* --- storage access --- */

            function name() -> n {
                n := sload(nameSlot())
            }

            function symbol() -> s {
                s := sload(symbolSlot())
            }

            function owner() -> o {
                o := sload(ownerSlot())
            }
        }
    }
}
