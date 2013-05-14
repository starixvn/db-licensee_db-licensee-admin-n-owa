 set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go



ALTER   PROCEDURE [dbo].[OA_LicenseeProductUpdComm]
	@LicenseeID INT,
	@isAllowedMemberComm BIT=0,	
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
		SELECT 1 FROM bodb_licensee.dbo.Licensees WITH (NOLOCK) 
		WHERE LicenseeID=@LicenseeID
		)
	
	BEGIN 
		SELECT @ErrMsg='This feature has not  offer for LicenseeID='''+convert(varchar,@LicenseeID)+''''
				,@ErrCode=1
		Return
	END
ELSE
BEGIN	
		UPDATE bodb_Licensee.dbo.Licensees WITH(ROWLOCK, UPDLOCK)
			SET isAllowedMemberComm=@isAllowedMemberComm
			WHERE LicenseeID=@LicenseeID
		SELECT @ErrMsg='The Commission feature  has been change setting for  LicenseeID='''+convert(varchar,@LicenseeID)+'''successful'
						,@ErrCode=0
				Return			
END

----------------------------------------------------write log-------------------------------------------------------------------------------------------
SELECT @LogSPData = '<OA_LicenseeProductUpdComm="'+ COALESCE(CAST(@LicenseeID as VARCHAR(50)),SPACE(1)) + '" ' +
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
GRANT EXECUTE ON [dbo].[OA_LicenseeProductUpdComm] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_LicenseeProductUpdComm] TO [vnteam]