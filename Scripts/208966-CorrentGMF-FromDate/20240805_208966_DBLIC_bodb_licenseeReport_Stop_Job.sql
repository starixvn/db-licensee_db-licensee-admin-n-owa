/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20240805@Danny
	DB: DBLIC.bodb_licenseeReport
	Description: Disable job "bodb_LicenseeReport: DW - Generate Daily"
*/

USE msdb ;  
GO  

EXEC dbo.sp_update_job  
    @job_name = N'bodb_LicenseeReport: DW - Generate Daily',  
    @enabled = 0 ;  
GO  