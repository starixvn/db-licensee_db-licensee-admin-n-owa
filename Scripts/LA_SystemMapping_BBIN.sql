/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210510@Percy
	DB: DBCUST.bodb_licensee
	Task: Add System Mapping settings for BBIN
*/

use bodb_licensee
go

insert into dbo.LA_ChargeInfo_SystemMapping 
values (5560, 2), (5561, 2)
go