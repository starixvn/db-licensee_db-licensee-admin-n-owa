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
	-- EUR
	SELECT CONVERT(INT, 6) AS BaseCurrencyId, CONVERT(MONEY, 0) AS FromAmount, CONVERT(MONEY, 10000000) AS ToAmount, CONVERT(FLOAT, 0.08) AS Rate
	UNION ALL SELECT 6, 10000001, 100000000000, 0.07 -- 100,000,000,000 = Unlimited
	-- CNY
	UNION ALL SELECT 13, 0, 80000000, 0.08
	UNION ALL SELECT 13, 80000001, 100000000000, 0.07 -- 100,000,000,000 = Unlimited