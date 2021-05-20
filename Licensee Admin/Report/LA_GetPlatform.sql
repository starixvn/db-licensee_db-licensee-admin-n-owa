/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_GetPlatform]
AS

/*
	Created: 20210517@Percy
	DB: DBEXT-bodb02
	Description: Get BetFrom

	Revisions:
		- 20210517@Percy: Initialize function [RedmineID: #150899]
*/

BEGIN
	SET NOCOUNT ON

	SELECT DISTINCT DetailPlatform, SummaryPlatform
	FROM dbo.LA_f_BetFrom_Sel()
	ORDER BY SummaryPlatform
END
GO