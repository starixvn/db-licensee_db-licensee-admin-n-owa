/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_SportsGetAll]
AS

/*
	Created: 20140903@Florent
	DB: DBEXT.bodb02
	Task: Get all sport types of Sportsbook

	Revisions:
		- 20140903@Florent: Initialize SP [RedmineID: #103658]
*/

BEGIN
	SET NOCOUNT ON

	SELECT *
	FROM dbo.Sports WITH (NOLOCK)
	WHERE SportType <= 99
END
GO