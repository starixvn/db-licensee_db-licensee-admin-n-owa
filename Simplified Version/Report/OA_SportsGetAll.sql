/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[OA_SportsGetAll]
AS

/*
	Created: 20111122@Kos
	DB: DBEXT.bodb02
	Task: Get all sport types of Sportsbook

	Revisions:
		- 20120314@Henry: get only sports <= 99 [RedmineID: #103658]
*/

BEGIN  
	SET NOCOUNT ON   

	SELECT Sporttype, SportName
	FROM dbo.Sports WITH (NOLOCK)
	WHERE sporttype <= 99
END  
GO