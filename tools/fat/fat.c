#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef uint8_t bool;
#define true 1
#define false 0

typedef struct
{
    uint8_t BootJumpInstruction[3];
    uint8_t OemIdentifier[8];
    uint16_t BytesPerSector;
    uint8_t SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t FatCount;
    uint16_t DirEntryCount;
    uint16_t TotalSectors;
    uint8_t MediaDescriptorType;
    uint16_t SectorsPerFat;
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;

    // Extended Boot Record
    uint8_t DriveNumber;
    uint8_t _Reserved;
    uint8_t Signature;
    uint32_t VolumeId;          
    uint8_t VolumeLabel[11]; 
    uint8_t SystemId[8];

} __attribute__((packed)) BootSector; // dont add padding bytes to DS

typedef struct 
{
    uint8_t Name[11];
    uint8_t Attributes;
    uint8_t _Reserved;
    uint8_t CreatedTimeTenths;
    uint16_t CreatedTime;
    uint16_t CreatedDate;
    uint16_t AccessedDate;
    uint16_t FirstClusterHigh;
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;
    uint32_t Size;
} __attribute__((packed)) DirectoryEntry;


BootSector g_BootSector;
uint8_t* g_Fat = NULL;
DirectoryEntry* g_RootDirectory = NULL; // Array of Directory Entries

bool readBootSector(FILE* disk)
{
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

bool readSectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut)
{
    bool ok = true;
    ok = ok && (fseek(disk, lba * g_BootSector.BytesPerSector, SEEK_SET) == 0); // Seek to right position in disk
    ok = ok && (fread(bufferOut, g_BootSector.BytesPerSector, count, disk) == count); // Read no. of sector from location
    return ok;
}

// Read File Allocation Table into memory
bool readFat(FILE* disk)
{
    g_Fat = (uint8_t*) malloc(g_BootSector.SectorsPerFat * g_BootSector.BytesPerSector);
    return readSectors(disk, g_BootSector.ReservedSectors, g_BootSector.SectorsPerFat, g_Fat); // Read the file allocation table that starts after Reserved Sector
}

bool readRootDirectory(FILE* disk)
{
    uint32_t lba = g_BootSector.ReservedSectors + g_BootSector.SectorsPerFat * g_BootSector.FatCount; // Calculate which sector
    uint32_t size = sizeof(DirectoryEntry) * g_BootSector.DirEntryCount; // Determine Size
    uint32_t sectors = (size / g_BootSector.BytesPerSector); // How many sectors to read
    
    if(size % g_BootSector.BytesPerSector > 0)
        sectors++;

    g_RootDirectory = (DirectoryEntry*) malloc(sectors * g_BootSector.BytesPerSector);
    return readSectors(disk, lba, sectors, g_RootDirectory);
}

DirectoryEntry* findFile(const char* name)
{
    for(uint32_t i=0; i < g_BootSector.DirEntryCount; i++)
    {
        if(memcmp(name, g_RootDirectory[i].Name, 11) == 0)
        {
            return &g_RootDirectory[i];
        }
    }
    
    return NULL;
}

int main(int argc, char** argv)
{
    if(argc < 3)
    {
        printf("Syntax: %s <disk image> <filename>\n", argv[0]);
        return -1;
    }

    // Read the bootsector
    FILE* disk = fopen(argv[1], "rb");
    if(!disk)
    {
        fprintf(stderr, "Cannot open disk image %s!", argv[1]);
        return -1;
    }

    if(!readBootSector(disk))
    {
        fprintf(stderr, "Could not read boot sector!\n");
        return -2;
    }

    if(!readFat(disk))
    {
        fprintf(stderr, "Could not read FAT sector!\n");
        free(g_Fat);
        return -3;
    }

    if(!readRootDirectory(disk))
    {
        fprintf(stderr, "Could not read Root Directory!\n");
        free(g_RootDirectory);
        return -4;
    }

    DirectoryEntry* fileEntry = findFile(argv[2]);
    if(!fileEntry)
    {
        fprintf(stderr, "Could not find file %s in root directory!\n", argv[2]);
        free(fileEntry);
        return -5;
    }

    
    free(g_Fat);
    free(g_RootDirectory);
    return 0;
}
