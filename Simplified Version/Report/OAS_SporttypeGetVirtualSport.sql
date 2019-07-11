/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[OAS_SporttypeGetVirtualSport]
AS
/*    
	Created: Henry
	Date: 2012-08-28
	Task: Get all sport types for virtual sport
	DB: DBEXT.bodb02
     
	Revisions:
		- 20120828@Henry: Initialize SP
*/  

BEGIN  
	SET NOCOUNT ON   

	SELECT Sporttype,SportName  
	FROM Sports WITH (NOLOCK)  
	WHERE sporttype BETWEEN 180 AND 199
	ORDER BY sporttype ASC 
END
GO