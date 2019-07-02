/*<info serverAlias="DBLIC-bodb_Licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_Licensee
GO

CREATE FUNCTION [dbo].[LA_f_LicenseeEventLog]
(
)
RETURNS TABLE
AS

/*
	Created: 20190510@Percy
	DB: DBLIC.bodb_Licensee
	Task: Change table LicenseeEventLog to function

	Revisions:
		- 20190510@Percy: Initialize function [RedmineID: #103658]
*/

RETURN
	SELECT	CONVERT(INT, 3) AS ObjectID
			,CONVERT(INT, 4) AS SystemID
			,CONVERT(INT, NULL) AS ProductID
			,CONVERT(INT, 3) AS ActionID
			,CONVERT(DATETIME, '2013-10-01 00:00:00.000') AS FromDate
			,CONVERT(DATETIME, '2050-01-01 00:00:00.000') AS ToDate
			,CONVERT(VARCHAR(100), NULL) AS AdditionData1
			,CONVERT(DATETIME, '2013-10-30 22:45:42.717') AS LogDate

	UNION ALL SELECT 5, 4, NULL, 3, '2013-10-01', '2050-01-01', NULL, '2013-10-30 22:45:42.717'
	UNION ALL SELECT 4, 4, 2, 5, '2013-09-01', '2013-09-30', NULL, '2013-10-30 22:45:42.717'
	UNION ALL SELECT 4, 4, 4, 5, '2013-09-01', '2013-09-30', NULL, '2013-10-30 22:45:42.717'
GO