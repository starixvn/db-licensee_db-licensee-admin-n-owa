/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_SporttypeGetVirtualSport]
AS

/*
	Created: Florent    
	Date: 2014-08-28
	Task: Get all sport types for virtual sport 
	DB: DBEXT.bodb02    
     
    Revisions:
		- 20140828@Florent: Initialize SP
*/  

BEGIN  
	SET NOCOUNT ON   

	SELECT Sporttype, SportName
	FROM dbo.Sports WITH (NOLOCK)
	WHERE sporttype BETWEEN 180 AND 199
	ORDER BY sporttype ASC
END  
GO