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
*/

RETURN
	SELECT OrderDetail, OrderSummary, betfrom, DetailPlatform, SummaryPlatform
	FROM (
		VALUES
			(1, 1, 'x', 'Desktop New Asia', 'Desktop'),
			(2, 1, 'a', 'Desktop China', 'Desktop'),
			(2, 1, 'z', 'Desktop China', 'Desktop'),
			(3, 1, '9', 'Desktop Others', 'Desktop'),
			(3, 1, '>', 'Desktop Others', 'Desktop'),
			(4, 2, 'l', 'Mobile Standard', 'Mobile'),
			(5, 2, '%', 'Mobile Euro', 'Mobile'),
			(6, 2, 'c', 'Mobile Compact', 'Mobile'),
			(6, 2, '@', 'Mobile Compact', 'Mobile'),
			(7, 2, '7', 'Mobile Others', 'Mobile'),
			(7, 2, '8', 'Mobile Others', 'Mobile'),
			(7, 2, '_', 'Mobile Others', 'Mobile'),
			(8, 1, '1', 'E-Sports Desktop', 'Desktop'),
			(8, 1, '4', 'E-Sports Desktop', 'Desktop'),
			(9, 2, '2', 'E-Sports Mobile', 'Mobile'),
			(9, 2, '5', 'E-Sports Mobile', 'Mobile'),
			(10, 2, '3', 'E-Sports APP', 'Mobile'),
			(10, 2, '6', 'E-Sports APP', 'Mobile'),
			(11, 2, 'o', 'Mobile APP', 'Mobile'),
			(11, 2, '~', 'Mobile APP', 'Mobile'),
			(12, 2, '0', 'Native APP', 'Mobile'),
			(13, 2, 'r', 'Tablet', 'Mobile'),
			(14, 4, 't', 'Deep Link', 'Others'),
			(15, 2, 'm', 'WAP', 'Mobile'),
			(16, 3, 'v', 'Odds Feed', 'Odds Feed'),
			(17, 4, 'd', 'Others', 'Others'),
			(17, 4, 'g', 'Others', 'Others'),
			(17, 4, 'e', 'Others', 'Others'),
			(17, 4, 'u', 'Others', 'Others'),
			(17, 4, '^', 'Others', 'Others')
	) d (OrderDetail, OrderSummary, betfrom, DetailPlatform, SummaryPlatform)
GO