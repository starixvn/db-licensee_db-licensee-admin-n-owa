/*<info serverAlias="DBCTG-bodb02" isFunction="0" isNested=""></info>*/
/*
	Created: 20250805@Danny
	DB: DBCTG.bodb02
	Task: update licensee transfer pool status [Redmind: #234675]

*/

USE bodb02

GO 

-- 3 rows
UPDATE dbo.LicenseeTransferPool WITH(ROWLOCK)
SET	 Status = 'New'
WHERE Status = 'InProgress'

