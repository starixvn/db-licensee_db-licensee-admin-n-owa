 set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go



ALTER PROCEDURE [dbo].[OA_LicenseeProductUpd]
	@LicenseeID INT,
	@ProductID INT,
	@isComm BIT=0,
	@isWL	BIT=0,
	@EffectiveDate SMALLDATETIME,
	@modifyDate SMALLDATETIME,
	@usrID INT ,
	@IP	  VARCHAR(30),		
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
DECLARE @startRun DATETIME
DECLARE @endRun DATETIME
DECLARE @duration INT
DECLARE @LogSPData VARCHAR(5000)
SET @startRun = GETDATE()


		
IF NOT EXISTS (
		SELECT 1 FROM bodb_licensee.dbo.LicenseeProduct3rd WITH (NOLOCK) 
		WHERE LicenseeID=@LicenseeID
			AND ProductID=@ProductID
		)
	
	BEGIN 
		SELECT @ErrMsg='This product has not  offer for LicenseeID='''+convert(varchar,@LicenseeID)+''''
				,@ErrCode=1
		Return
	END
ELSE
BEGIN	
		IF @ProductID IN (1,2,3,4,5) -- Number Game,Horse Racing 
			BEGIN 
				
					UPDATE bodb_licensee.dbo.LicenseeProduct3rd  WITH(ROWLOCK, UPDLOCK)
					SET Comm=@isComm
					WHERE LicenseeID=@licenseeID
						AND ProductID=@ProductID
					
					UPDATE bodb_licensee.dbo.LicenseeProduct3rd  WITH(ROWLOCK, UPDLOCK)
					SET Winloss=@isWL
					WHERE LicenseeID=@licenseeID
						  AND ProductID=@ProductID
					UPDATE bodb_licensee.dbo.LicenseeProduct3rd  WITH(ROWLOCK, UPDLOCK)
					SET EffectiveDate=@EffectiveDate
					WHERE LicenseeID=@licenseeID
						  AND ProductID=@ProductID	  
				
			END 
		
		SELECT @ErrMsg='The ProductID ='''+convert(varchar,@ProductID)+'''has been change setting for  LicenseeID='''+convert(varchar,@LicenseeID)+''' successful '
						,@ErrCode=0
				Return			
END
----------------------------------------------------write log-------------------------------------------------------------------------------------------
SELECT @LogSPData = '<OA_LicenseeProductUpd="'+ COALESCE(CAST(@LicenseeID as VARCHAR(50)),SPACE(1)) + '" ' +
					'UserID="'+ COALESCE(CAST(@usrID as VARCHAR(50)),SPACE(1)) + '" ' +
					'CustID="'+ COALESCE(CAST(NULL as VARCHAR(50)),SPACE(1)) + '" ' +
					'Language="'+ COALESCE(CAST(NULL as VARCHAR(10)),SPACE(1)) + '" ' +
					'IP="'+ COALESCE(CAST(@IP as VARCHAR(40)),SPACE(1)) + '" ' +
					'ErrCode="'+ COALESCE(CAST(@ErrCode as VARCHAR(50)),SPACE(1)) + '" ' +
					'ErrMsg="'+ COALESCE(CAST(@ErrMsg as VARCHAR(5000)),SPACE(1))+ '" />'


SET @endRun = GETDATE()
SET @duration  = datediff (millisecond,@startRun,@endRun)

EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP 
		@UserID = @usrID,
		@TrackingValue = @LogSPData,
		@TrackingValue2 = '',
		@duration = @duration
-------------------------------------------------------------------------------------------------------------------------------------------------------------
GO
GRANT EXECUTE ON [dbo].[OA_LicenseeProductUpd] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_LicenseeProductUpd] TO [vnteam]