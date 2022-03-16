/*<info serverAlias="DBLIC-bodb_Licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_Licensee
GO

ALTER FUNCTION [dbo].[LA_f_TierRebateSetting]()
RETURNS TABLE
AS

/*
	Created: 20220210@Percy
	DB: DBLIC-bodb_Licensee
	Task: Tier Rebate Setting

	Revisions:
		- 20220210@Percy: Initialize function [RedmineID: #163495]
*/

RETURN
	SELECT CONVERT(MONEY, 0) AS FromAmount, CONVERT(MONEY, 80000000) AS ToAmount, CONVERT(FLOAT, 0.08) AS Rate
	UNION ALL SELECT 80000001, 100000000000, 0.07 -- 100,000,000,000 = Unlimited