/*<info serverAlias="DBEXT-bodb02" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb02
GO

ALTER FUNCTION [dbo].[LA_f_BetFrom_Sel]
(
)
RETURNS TABLE
AS

/*
	Created: 20210517@Percy
	DB: DBEXT-bodb02
	Description: Get BetFrom

	Revisions:
		- 20210517@Percy: Initialize function [RedmineID: #150899]
		- 20211213@Danny: Add new betfrom [RedmineID: #165971]
*/

RETURN
	SELECT OrderDetail, OrderSummary, betfrom, DetailPlatform, SummaryPlatform
	FROM (
		VALUES
			(10, 10, 'x', 'Desktop New Asia', 'Desktop'),
			(20, 10, 'a', 'Desktop China', 'Desktop'),
			(20, 10, 'z', 'Desktop China', 'Desktop'),
			(20, 10, '[', 'Desktop China', 'Desktop'),
			(30, 10, '9', 'Desktop Others', 'Desktop'),
			(30, 10, '>', 'Desktop Others', 'Desktop'),
			(40, 20, 'l', 'Mobile Standard', 'Mobile'),
			(40, 20, ']', 'Mobile Standard', 'Mobile'),
			(50, 20, '%', 'Mobile Euro', 'Mobile'),
			(60, 20, 'c', 'Mobile Compact', 'Mobile'),
			(60, 20, '@', 'Mobile Compact', 'Mobile'),
			(70, 20, '7', 'Mobile Others', 'Mobile'),
			(70, 20, '8', 'Mobile Others', 'Mobile'),
			(70, 20, '_', 'Mobile Others', 'Mobile'),
			(70, 20, '.', 'Mobile Others', 'Mobile'),
			(70, 20, '$', 'Mobile Others', 'Mobile'),
			(80, 10, '1', 'E-Sports Desktop', 'Desktop'),
			(80, 10, '4', 'E-Sports Desktop', 'Desktop'),
			(90, 20, '2', 'E-Sports Mobile', 'Mobile'),
			(90, 20, '5', 'E-Sports Mobile', 'Mobile'),
			(100, 20, '3', 'E-Sports APP', 'Mobile'),
			(100, 20, '6', 'E-Sports APP', 'Mobile'),
			(110, 20, 'o', 'Mobile APP', 'Mobile'),
			(110, 20, '~', 'Mobile APP', 'Mobile'),
			(120, 20, '0', 'Native APP', 'Mobile'),
			(130, 20, 'r', 'Tablet', 'Mobile'),
			(140, 40, 't', 'Deep Link', 'Others'),
			(150, 20, 'm', 'WAP', 'Mobile'),
			(160, 30, 'v', 'Odds Feed', 'Odds Feed'),
			(170, 40, 'd', 'Others', 'Others'),
			(170, 40, 'g', 'Others', 'Others'),
			(170, 40, 'e', 'Others', 'Others'),
			(170, 40, 'u', 'Others', 'Others'),
			(180, 50, '^', 'Odds Direct API', 'Odds Direct API')
	) d (OrderDetail, OrderSummary, betfrom, DetailPlatform, SummaryPlatform)
GO