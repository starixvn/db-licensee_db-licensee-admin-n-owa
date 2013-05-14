 set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go


ALTER   PROCEDURE [dbo].[OA_LicenseeProductAdminRole]
@ErrCode int = 0 OUTPUT , 
@ErrMsg nvarchar(1000) = '' OUTPUT 
AS
/*  
 * Created: 20130116@Jim
 * Task :  Licensee Product & feature management
 * DB: DB052.bodb02  
 *  
 * Revisions:     
 
 * Parameter explanation
	
*/
SET NOCOUNT ON 
BEGIN
	DECLARE @tblSpecialUser AS TABLE (UsrID INT)
	DECLARE @tblLicensee AS TABLE (LicenseeID INT)	
	
	INSERT INTO @tblLicensee
	SELECT DISTINCT LicenseeID
	FROM bodb_Licensee.dbo.LicenseeFunctions  WITH (NOLOCK)

	INSERT INTO @tblSpecialUser
	SELECT UserID
	FROM bodb_licensee.dbo.Users WITH (NOLOCK)
	WHERE UserID IN (
					1,-- dbaThien
					2,--dbaHenry
					3,--pgmViet
					8,--dbaJamie
					9,--Bill
					11,--pgmPhuong
					63,--Martin
					64,--Justin
					65,--Charles
					74,--pgmkiwi
					79,--dbaLukas
					80,--pgmHanh
					81,--dbaVinh
					157,--pgmAnn
					160,--Anthony
					339,--Sean
					340,--Byron
					341,--Sam
					369 --dbaDon
					)
	

-------------------------------------------------------------Admin of each licensee OR Special User ----------------------------------------------------------------------------
	DECLARE @MaxID INT
	DECLARE @i INT 

	SELECT @MaxID=Max(LicenseeID),@i=min(LicenseeID) FROM @tblLicensee
	WHILE (@i<=@MaxID)
		BEGIN
			------ delete conflict data 
			DELETE 
			FROM bodb_Licensee.dbo.LicenseeUserFunctions 
			WHERE LicenseeID=@i AND userID IN (
												SELECT userID 
												FROM bodb_licensee.dbo.Users WITH (NOLOCK) 
												WHERE UserName LIKE 'Admin%'
												UNION
												SELECT UsrID FROM @tblSpecialUser
												)
			
			----- re-insert data 
			INSERT INTO bodb_Licensee.dbo.LicenseeUserFunctions (UserID,FunctionID,LicenseeID)
			SELECT u.UserID,f.FunctionID,f.LicenseeID
			FROM bodb_Licensee.dbo.LicenseeFunctions f WITH (NOLOCK)
				INNER JOIN bodb_licensee.dbo.LicenseeUser u WITH (NOLOCK) ON f.LicenseeID=u.LicenseeID 
			WHERE f.LicenseeID=@i
			AND u.isActive=1
			AND u.UserID IN (SELECT userID FROM bodb_licensee.dbo.Users WITH (NOLOCK) WHERE UserName LIKE 'Admin%'
							 UNION 
							 SELECT UsrID FROM @tblSpecialUser)
			
			SET @i=@i+1
			
		END 
END

---------------------------------------------------------------------------------------------------------------------------------------------------------------
	

GO
GRANT EXECUTE ON [dbo].[OA_LicenseeProductAdminRole] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_LicenseeProductAdminRole] TO [vnteam]


